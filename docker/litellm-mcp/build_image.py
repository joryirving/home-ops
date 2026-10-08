#!/usr/bin/env python3
"""Build and exercise the amd64 LiteLLM image using its installed MCP stdio SDK."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any


BASE = (
    "ghcr.io/berriai/litellm-database:v1.104.0@"
    "sha256:fbe28229d2d02181c0a7d9df9599de614b491f3d897d2d7da18404f088310218"
)
ROOT = Path(__file__).resolve().parent
HANDSHAKE_TIMEOUT = 30.0
PROXY_STARTUP_TIMEOUT = 180.0
COMMAND_TIMEOUT = 300
APPROVED_TEMP_ROOT = Path("/private/var/folders/jh/4ss4bk3x1zgd8ff7nm_j4r0c0000gn/T/opencode")


def temporary_directory(prefix: str, *, dir: str | Path | None = None) -> tempfile.TemporaryDirectory[str]:
    if dir is not None:
        return tempfile.TemporaryDirectory(prefix=prefix, dir=dir)
    temp_root = APPROVED_TEMP_ROOT if APPROVED_TEMP_ROOT.is_dir() else None
    return tempfile.TemporaryDirectory(prefix=prefix, dir=temp_root)


def run(command: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
    kwargs.setdefault("timeout", COMMAND_TIMEOUT)
    return subprocess.run(command, check=True, text=True, **kwargs)


def image_config(image: str) -> dict[str, Any]:
    raw = run(["docker", "image", "inspect", "--platform", "linux/amd64", image], capture_output=True).stdout
    return json.loads(raw)[0]["Config"]


def verify_runtime(image: str) -> None:
    base = image_config(BASE)
    custom = image_config(image)
    for key in ("Entrypoint", "Cmd", "WorkingDir"):
        if custom.get(key) != base.get(key):
            raise RuntimeError(f"custom image changed LiteLLM base {key}: {custom.get(key)!r} != {base.get(key)!r}")
    if custom.get("User") != "1000:1000":
        raise RuntimeError(f"expected nonroot image user 1000:1000, got {custom.get('User')!r}")

    result = run(
        [
            "docker", "run", "--rm", "--platform", "linux/amd64", "--tmpfs", "/app/chatgpt_tokens:rw,nosuid,nodev,mode=0770,uid=1000,gid=1000",
            "--entrypoint", "/app/.venv/bin/python3", image,
            "-c",
            "import os,subprocess,sys; "
            "print('NODE='+subprocess.check_output(['/usr/local/bin/node','--version'],text=True).strip()); "
            "print('UID='+str(os.getuid())); "
            "print('PYTHON='+sys.version.split()[0]); "
            "print('MCP_SDK='+__import__('mcp').__file__); "
            "print('HOME_WRITABLE='+str(os.access(os.environ['HOME'],os.W_OK))); "
            "paths=['/tmp','/app/chatgpt_tokens','/opt/prisma/binaries']; "
            "print('WRITABLE='+repr({p:os.access(p,os.W_OK) for p in paths}))",
        ],
        capture_output=True,
    ).stdout
    if not all(check in result for check in ("NODE=v24.", "UID=1000", "HOME_WRITABLE=True", "MCP_SDK=")):
        raise RuntimeError(f"unexpected runtime identity, home, MCP SDK, or Node: {result.strip()}")
    if "'/tmp': True" not in result or "'/app/chatgpt_tokens': True" not in result:
        raise RuntimeError(f"expected writable /tmp and UI PVC paths for uid 1000: {result.strip()}")
    if "'/opt/prisma/binaries': True" in result:
        raise RuntimeError("uid 1000 unexpectedly has write access to the base image Prisma binary cache")
    print(result.strip())


def verify_proxy_startup(image: str) -> None:
    """Start LiteLLM with its base entrypoint script and standard port."""
    name = f"litellm-mcp-proxy-check-{uuid.uuid4().hex[:8]}"
    try:
        run(
            ["docker", "run", "-d", "--name", name, "--platform", "linux/amd64", "--user", "1000:1000",
             "--env", "LITELLM_MASTER_KEY=sk-smoke-only-not-a-real-secret", "--group-add", "1000", "--security-opt", "no-new-privileges", "--cap-drop", "ALL",
             "--read-only", "--tmpfs", "/tmp:rw,nosuid,nodev,mode=1777,uid=1000,gid=1000",
             "--tmpfs", "/app/chatgpt_tokens:rw,nosuid,nodev,mode=0777,uid=1000,gid=1000",
             "--tmpfs", "/app/cache:rw,nosuid,nodev,mode=0777,uid=1000,gid=1000",
             "--tmpfs", "/var/run/litellm-mcp:rw,nosuid,nodev,noexec,mode=0555,uid=1000,gid=1000",
             "--entrypoint", "/bin/sh", image, "-ec",
             "printf 'model_list: []\\ngeneral_settings:\\n  store_model_in_db: false\\n' > /tmp/litellm-config.yaml; "
             "exec /app/docker/prod_entrypoint.sh --port 4000 --config /tmp/litellm-config.yaml"],
            capture_output=True,
        )
        deadline = time.monotonic() + PROXY_STARTUP_TIMEOUT
        ready = False
        last_logs = ""
        while time.monotonic() < deadline:
            state = json.loads(
                run(["docker", "inspect", name, "--format", "{{json .State}}"], capture_output=True).stdout
            )
            logs = subprocess.run(["docker", "logs", name], text=True, capture_output=True)
            last_logs = logs.stdout + logs.stderr
            if not state["Running"]:
                logs = subprocess.run(["docker", "logs", name], text=True, capture_output=True)
                last_logs = logs.stdout + logs.stderr
                raise RuntimeError(f"LiteLLM exited with status {state['ExitCode']}: {last_logs[-2000:]}: {state!r}")
            if "Application startup complete" in last_logs or "Uvicorn running on" in last_logs:
                ready = True
                break
            time.sleep(1)
        if not ready:
            raise RuntimeError(f"LiteLLM did not complete startup: {last_logs[-2000:]}")
        health = None
        health_error = ""
        for _ in range(30):
            probe = subprocess.run(
                ["docker", "exec", name, "/app/.venv/bin/python3", "-c",
                 "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:4000/health/liveliness', timeout=5).status)"],
                capture_output=True, text=True, timeout=10,
            )
            health_error = probe.stderr
            if probe.returncode == 0:
                health = probe.stdout.strip()
                break
            time.sleep(2)
        if health != "200":
            logs = subprocess.run(["docker", "logs", name], text=True, capture_output=True)
            details = logs.stdout + logs.stderr
            raise RuntimeError(f"LiteLLM proxy health endpoint returned {health!r}: {health_error[-1000:]} {details[-2000:]}")
        print("LiteLLM proxy startup and /health/liveliness succeeded with base ENTRYPOINT/CMD and --port 4000")
    finally:
        subprocess.run(["docker", "rm", "-f", name], text=True, capture_output=True)


def temp_secret_mounts(server_name: str) -> tuple[Any, list[Path]]:
    directory = temporary_directory(f"litellm-mcp-{server_name}-")
    try:
        directory_root = Path(directory.name).resolve()
        root = directory_root / server_name
        root.mkdir()
        keys = {
            "arr": ("SONARR_API_KEY", "RADARR_API_KEY", "PROWLARR_API_KEY"),
            "seerr": ("SEERR_API_KEY",),
            "github": ("token",),
            "dispatch": ("token",),
        }[server_name]
        paths: list[Path] = []
        for key in keys:
            path = root / key
            path.write_text(f"offline-smoke-{server_name}-{key}", encoding="utf-8")
            os.chmod(path, 0o444)
            paths.append(path)
        return directory, paths
    except BaseException:
        directory.cleanup()
        raise


def smoke_via_installed_sdk(image: str, server_name: str) -> dict[str, Any]:
    """Run the base image's MCP stdio client against its own launcher subprocess."""
    directory = None
    try:
        directory, secret_paths = temp_secret_mounts(server_name)
        test_code = f'''import asyncio, json, time
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def main():
    params = StdioServerParameters(
        command="/app/.venv/bin/python3",
        args=["/opt/mcp/launch.py", "{server_name}"],
        env={{
            "HOME": "/home/nonroot",
            "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/app/.venv/bin",
            "LITELLM_MASTER_KEY": "proxy-admin-must-not-leak",
            "OPENAI_API_KEY": "provider-must-not-leak",
            "KUBERNETES_SERVICE_HOST": "service-account-must-not-leak",
        }},
    )
    started = time.monotonic()
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await asyncio.wait_for(session.list_tools(), timeout={HANDSHAKE_TIMEOUT})
            tools = [{{"name": tool.name, "description": tool.description}} for tool in result.tools]
            if not tools:
                raise RuntimeError("server returned no tools")
            print(json.dumps({{"server": "{server_name}", "tools": tools,
                "elapsed_seconds": round(time.monotonic() - started, 3)}}))

asyncio.run(main())
'''
        script = ["set -eu", f"mkdir -p /var/run/litellm-mcp/{server_name}", "umask 077"]
        for index, path in enumerate(secret_paths):
            destination = f"/var/run/litellm-mcp/{server_name}/{path.name}"
            marker = f"LITELLM_MCP_SECRET_{index}"
            value = path.read_text(encoding="utf-8")
            script.extend([f"cat > {destination} <<'{marker}'", value, marker, f"chmod 0440 {destination}"])
        script.extend([
            "cat > /tmp/litellm_mcp_smoke.py <<'LITELLM_MCP_CLIENT'",
            test_code,
            "LITELLM_MCP_CLIENT",
            "exec /app/.venv/bin/python3 /tmp/litellm_mcp_smoke.py",
        ])
        command = [
            "docker", "run", "--rm", "-i", "--platform", "linux/amd64", "--user", "1000:1000",
            "--tmpfs", "/var/run/litellm-mcp:rw,nosuid,nodev,noexec,mode=0755,uid=1000,gid=1000",
            "--tmpfs", "/tmp:rw,nosuid,nodev,mode=1777",
            "--entrypoint", "/bin/sh", image, "-s",
        ]
        started = time.monotonic()
        proc = run(command, input="\n".join(script) + "\n", capture_output=True, timeout=HANDSHAKE_TIMEOUT + 20)
        result = json.loads(proc.stdout.strip().splitlines()[-1])
        result["elapsed_seconds"] = round(time.monotonic() - started, 3)
        if server_name == "github":
            names = {tool["name"] for tool in result["tools"]}
            expected = {"search_repositories", "search_code"}
            if not expected.issubset(names):
                raise RuntimeError(f"GitHub omitted default search tools {sorted(expected - names)}")
            if any("proxy-admin-must-not-leak" in str(tool) or "provider-must-not-leak" in str(tool) for tool in result["tools"]):
                raise RuntimeError("GitHub MCP tools leaked parent proxy/provider credentials")
        return result
    finally:
        if directory is not None:
            directory.cleanup()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", default="ghcr.io/joryirving/litellm-mcp:1.104.0-mcp1")
    parser.add_argument("--skip-proxy-start", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()

    if not args.skip_build:
        run(["docker", "build", "--platform", "linux/amd64", "-t", args.image, str(ROOT)])
    verify_runtime(args.image)
    if not args.skip_proxy_start:
        verify_proxy_startup(args.image)
    for name in ("arr", "seerr", "github", "dispatch"):
        print(json.dumps(smoke_via_installed_sdk(args.image, name), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
