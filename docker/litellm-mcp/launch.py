#!/usr/bin/env python3
"""Launch one bundled stdio MCP server with a fixed child environment."""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence


SECRET_ROOT = Path("/var/run/litellm-mcp")
NODE = "/usr/local/bin/node"
PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/app/.venv/bin"


@dataclass(frozen=True)
class Server:
    command: str
    args: tuple[str, ...]
    env: Mapping[str, str]
    secrets: Mapping[str, str]


SERVERS: Mapping[str, Server] = {
    "arr": Server(
        command=NODE,
        args=("/opt/mcp/node_modules/mcp-arr-server/dist/index.js",),
        env={
            "HOME": "/tmp",
            "NODE_ENV": "production",
            "PATH": PATH,
            "RADARR_URL": "http://radarr.downloads",
            "SONARR_URL": "http://sonarr.downloads",
            "TMPDIR": "/tmp",
            "PROWLARR_URL": "http://prowlarr.downloads",
        },
        secrets={
            "PROWLARR_API_KEY": "PROWLARR_API_KEY",
            "RADARR_API_KEY": "RADARR_API_KEY",
            "SONARR_API_KEY": "SONARR_API_KEY",
        },
    ),
    "dispatch": Server(
        command=NODE,
        args=(
            "/opt/mcp/dispatch/node_modules/.bin/tsx",
            "/opt/mcp/dispatch/src/mcp/server.ts",
        ),
        env={
            "DISPATCH_URL": "http://dispatch.llm:3000",
            "HOME": "/tmp",
            "NODE_ENV": "production",
            "PATH": PATH,
            "TMPDIR": "/tmp",
        },
        secrets={"token": "DISPATCH_AGENT_TOKEN"},
    ),
    "github": Server(
        command="/opt/mcp/bin/github-mcp-server",
        args=("stdio",),
        env={
            "GITHUB_API_URL": "https://api.github.com",
            "HOME": "/tmp",
            "LOG_LEVEL": "info",
            "PATH": PATH,
            "SSL_CERT_FILE": "/etc/ssl/certs/ca-certificates.crt",
            "TMPDIR": "/tmp",
        },
        secrets={"token": "GITHUB_PERSONAL_ACCESS_TOKEN"},
    ),
    "seerr": Server(
        command=NODE,
        args=("/opt/mcp/node_modules/@jhomen368/overseerr-mcp/build/index.js",),
        env={
            "HOME": "/tmp",
            "NODE_ENV": "production",
            "PATH": PATH,
            "SEERR_URL": "http://seerr.media",
            "TMPDIR": "/tmp",
        },
        secrets={"SEERR_API_KEY": "SEERR_API_KEY"},
    ),
}


class LaunchError(Exception):
    """A safe-to-report launch configuration or secret-file error."""


def build_environment(server_name: str, secret_root: Path | None = None) -> dict[str, str]:
    secret_root = SECRET_ROOT if secret_root is None else secret_root
    try:
        server = SERVERS[server_name]
    except KeyError as exc:
        raise LaunchError(f"unknown MCP server: {server_name}") from exc

    child_env = dict(server.env)
    for key, child_name in server.secrets.items():
        secret_path = secret_root / server_name / key
        try:
            value = secret_path.read_text(encoding="utf-8").rstrip("\r\n")
        except (OSError, UnicodeError) as exc:
            raise LaunchError(f"cannot read required secret file for {server_name}: {key}") from exc
        if not value or "\x00" in value:
            raise LaunchError(f"required secret file is empty or invalid for {server_name}: {key}")
        child_env[child_name] = value

    return child_env


def main(argv: Sequence[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        print("usage: launch.py {arr|dispatch|github|seerr}", file=sys.stderr)
        return 2

    name = args[0]
    try:
        server = SERVERS[name]
        env = build_environment(name)
    except (KeyError, LaunchError) as exc:
        message = str(exc) if isinstance(exc, LaunchError) else f"unknown MCP server: {name}"
        print(f"[litellm-mcp] {message}", file=sys.stderr)
        return 2

    argv = [server.command, *server.args]
    try:
        os.execvpe(server.command, argv, env)
    except OSError as exc:
        reason = exc.strerror or type(exc).__name__
        print(f"[litellm-mcp] cannot execute {name} MCP server: {reason}", file=sys.stderr)
        return 127
    return 127


if __name__ == "__main__":
    raise SystemExit(main())
