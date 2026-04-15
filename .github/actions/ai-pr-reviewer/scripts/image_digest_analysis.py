import json
import re
from pathlib import Path
from urllib import parse
import subprocess
import sys

def http_json(url, headers=None):
    cmd = [
        "curl",
        "-fsSL",
        "--connect-timeout",
        "20",
        "--max-time",
        "40",
        url,
    ]
    if headers:
        for key, value in headers.items():
            cmd.extend(["-H", f"{key}: {value}"])
    try:
        raw = subprocess.check_output(cmd)
        return json.loads(raw.decode("utf-8", errors="replace"))
    except Exception as e:
        raise RuntimeError(f"HTTP request failed: {e}")

def registry_targets(repo: str):
    if repo.startswith("docker.io/"):
        repo_path = repo[len("docker.io/"):]
        token_url = (
            "https://auth.docker.io/token?service=registry.docker.io&scope="
            + parse.quote(f"repository:{repo_path}:pull", safe=":")
        )
        base_url = "https://registry-1.docker.io"
        return repo_path, token_url, base_url
    if repo.startswith("ghcr.io/"):
        repo_path = repo[len("ghcr.io/"):]
        token_url = (
            "https://ghcr.io/token?scope="
            + parse.quote(f"repository:{repo_path}:pull", safe=":")
        )
        base_url = "https://ghcr.io"
        return repo_path, token_url, base_url
    if repo.count("/") == 1 and not repo.startswith(("quay.io/", "gcr.io/", "registry.k8s.io/")):
        repo_path = repo
        token_url = (
            "https://auth.docker.io/token?service=registry.docker.io&scope="
            + parse.quote(f"repository:{repo_path}:pull", safe=":")
        )
        base_url = "https://registry-1.docker.io"
        return repo_path, token_url, base_url
    raise ValueError(f"unsupported registry for repo {repo}")

def fetch_digest_metadata(repo: str, digest: str):
    result = {
        "repository": repo,
        "digest": digest,
        "mediaType": None,
        "configDigest": None,
        "created": None,
        "revision": None,
        "source": None,
        "version": None,
        "refName": None,
        "error": None,
        "indexManifests": None,
    }
    try:
        repo_path, token_url, base_url = registry_targets(repo)
        token = http_json(token_url).get("token")
        if not token:
            raise RuntimeError("registry token unavailable")

        accept = ", ".join(
            [
                "application/vnd.oci.image.manifest.v1+json",
                "application/vnd.docker.distribution.manifest.v2+json",
                "application/vnd.oci.image.index.v1+json",
                "application/vnd.docker.distribution.manifest.list.v2+json",
            ]
        )
        manifest = http_json(
            f"{base_url}/v2/{repo_path}/manifests/{digest}",
            headers={"Authorization": f"Bearer {token}", "Accept": accept},
        )
        result["mediaType"] = manifest.get("mediaType")

        manifests = manifest.get("manifests")
        if isinstance(manifests, list):
            result["indexManifests"] = [
                {
                    "digest": m.get("digest"),
                    "mediaType": m.get("mediaType"),
                    "platform": m.get("platform"),
                }
                for m in manifests[:6]
            ]

        config_digest = (manifest.get("config") or {}).get("digest")
        result["configDigest"] = config_digest
        if config_digest:
            config = http_json(
                f"{base_url}/v2/{repo_path}/blobs/{config_digest}",
                headers={"Authorization": f"Bearer {token}"},
            )
            labels = (
                (config.get("config") or {}).get("Labels")
                or (config.get("container_config") or {}).get("Labels")
                or {}
            )
            result["created"] = config.get("created")
            result["revision"] = labels.get("org.opencontainers.image.revision")
            result["source"] = labels.get("org.opencontainers.image.source")
            result["version"] = labels.get("org.opencontainers.image.version")
            result["refName"] = labels.get("org.opencontainers.image.ref.name")
    except Exception as exc:
        result["error"] = str(exc)
    return result

def github_repo_from_source(source: str | None):
    if not source:
        return None
    src = source.strip()
    m = re.search(r"github\.com[:/](?P<owner>[^/\s]+)/(?P<repo>[^/\s?#]+)", src, re.IGNORECASE)
    if m:
        owner = m.group("owner")
        repo = m.group("repo")
        if repo.endswith(".git"):
            repo = repo[:-4]
        return f"{owner}/{repo}"
    if re.match(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", src):
        return src
    return None

def guess_repo_from_image(image_repo: str):
    if image_repo.startswith("docker.io/"):
        tail = image_repo[len("docker.io/"):]
    elif image_repo.startswith("ghcr.io/"):
        tail = image_repo[len("ghcr.io/"):]
    else:
        tail = image_repo
    parts = tail.split("/")
    if len(parts) >= 2:
        return f"{parts[0]}/{parts[1]}"
    return None

def fetch_github_compare(repo: str | None, old_rev: str | None, new_rev: str | None):
    result = {
        "repo": repo,
        "old_revision": old_rev,
        "new_revision": new_rev,
        "status": None,
        "ahead_by": None,
        "behind_by": None,
        "total_commits": None,
        "html_url": None,
        "commits": [],
        "files": [],
        "error": None,
        "repo_source": None,
    }
    if not repo:
        result["error"] = "repo unavailable"
        return result
    if not old_rev or not new_rev:
        result["error"] = "revision labels missing"
        return result
    try:
        data = http_json(
            f"https://api.github.com/repos/{repo}/compare/{old_rev}...{new_rev}",
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": "home-ops-renovate-review",
            },
        )
        result["status"] = data.get("status")
        result["ahead_by"] = data.get("ahead_by")
        result["behind_by"] = data.get("behind_by")
        result["total_commits"] = data.get("total_commits")
        result["html_url"] = data.get("html_url")
        result["commits"] = [
            {
                "sha": (c.get("sha") or "")[:12],
                "message": ((c.get("commit") or {}).get("message") or "").splitlines()[0],
            }
            for c in (data.get("commits") or [])[:15]
        ]
        result["files"] = [
            {
                "filename": f.get("filename"),
                "status": f.get("status"),
                "changes": f.get("changes"),
            }
            for f in (data.get("files") or [])[:20]
        ]
    except Exception as exc:
        result["error"] = str(exc)
    return result

def short(value):
    if not value:
        return "(unknown)"
    if isinstance(value, str) and len(value) > 120:
        return value[:117] + "..."
    return str(value)

def parse_diff(diff_text: str):
    current_file = ""
    current_repo = ""
    buckets = {}

    for raw in diff_text.splitlines():
        m_file = re.match(r"^diff --git a/(.+?) b/(.+)$", raw)
        if m_file:
            current_file = m_file.group(2)
            current_repo = ""
            continue

        m_repo = re.match(r'^[ +\-]?\s*repository:\s*[\'"]?([^\'"\s,]+)', raw)
        if m_repo:
            current_repo = m_repo.group(1)
            continue

        m_tag = re.match(r'^([+-])\s*tag:\s*[\'"]?([^\'"\s,]+)', raw)
        if m_tag:
            sign = m_tag.group(1)
            tag_val = m_tag.group(2)
            m_digest = re.match(r"([^@\s]+)@sha256:([0-9a-f]{64})", tag_val)
            if m_digest and current_repo:
                tag_base = m_digest.group(1)
                digest = f"sha256:{m_digest.group(2)}"
                key = (current_file, current_repo, tag_base)
                buckets.setdefault(key, {"old": [], "new": []})
                buckets[key]["old" if sign == '-' else "new"].append(digest)
            elif current_repo:
                key = (current_file, current_repo, tag_val)
                buckets.setdefault(key, {"old": [], "new": []})
            continue

        m_digest_only = re.match(r'^([+-])\s*digest:\s*[\'"]?(sha256:[0-9a-f]{64})', raw)
        if m_digest_only and current_repo:
            sign = m_digest_only.group(1)
            digest = m_digest_only.group(2)
            tag_base = "(digest-only)"
            key = (current_file, current_repo, tag_base)
            buckets.setdefault(key, {"old": [], "new": []})
            buckets[key]["old" if sign == '-' else "new"].append(digest)
            continue

        m_image = re.match(r'^([+-])\s*image:\s*[\'"]?([^\'"\s,]+@sha256:[0-9a-f]{64})', raw)
        if m_image:
            sign = m_image.group(1)
            image_ref = m_image.group(2)
            repo_and_tag, digest = image_ref.split("@", 1)
            digest = digest if digest.startswith("sha256:") else f"sha256:{digest}"
            repo = repo_and_tag
            tag_base = "(inline-image)"
            if ":" in repo_and_tag.rsplit("/", 1)[-1]:
                repo, tag_base = repo_and_tag.rsplit(":", 1)
            key = (current_file, repo, tag_base)
            buckets.setdefault(key, {"old": [], "new": []})
            buckets[key]["old" if sign == '-' else "new"].append(digest)

    changes = []
    for (file_path, repo, tag_base), vals in buckets.items():
        pairs = min(len(vals["old"]), len(vals["new"]))
        for i in range(pairs):
            old = vals["old"][i]
            new = vals["new"][i]
            if old != new:
                changes.append(
                    {
                        "file": file_path,
                        "repository": repo,
                        "tag": tag_base,
                        "old_digest": old,
                        "new_digest": new,
                    }
                )
    return changes

def main():
    diff_path = Path("pr.diff.truncated")
    out_path = Path("image-digest-context.md")

    if not diff_path.exists():
        print("Error: pr.diff.truncated not found.")
        sys.exit(1)

    changes = parse_diff(diff_path.read_text(encoding="utf-8", errors="replace"))

    lines = []
    if not changes:
        lines.append("No image digest changes detected in PR diff.")
    else:
        lines.append("# Image Digest Provenance Analysis")
        lines.append("")
        for idx, change in enumerate(changes, start=1):
            old_meta = fetch_digest_metadata(change["repository"], change["old_digest"])
            new_meta = fetch_digest_metadata(change["repository"], change["new_digest"])

            lines.append(f"## Image {idx}: {change['repository']}")
            lines.append(f"- File: `{change['file']}`")
            lines.append(f"- Tag/variant: `{change['tag']}`")
            lines.append(f"- Old digest: `{change['old_digest']}`")
            lines.append(f"- New digest: `{change['new_digest']}`")
            lines.append(f"- Old revision: `{short(old_meta.get('revision'))}`")
            lines.append(f"- New revision: `{short(new_meta.get('revision'))}`")
            lines.append(f"- Old created: `{short(old_meta.get('created'))}`")
            lines.append(f"- New created: `{short(new_meta.get('created'))}`")
            lines.append(f"- Old source: `{short(old_meta.get('source'))}`")
            lines.append(f"- New source: `{short(new_meta.get('source'))}`")

            old_rev = old_meta.get("revision")
            new_rev = new_meta.get("revision")
            if old_rev and new_rev:
                if old_rev != new_rev:
                    lines.append("- Revision changed: **yes** (new code revision present)")
                else:
                    lines.append("- Revision changed: **no** (likely rebuild/republish of same source revision)")
            else:
                lines.append("- Revision changed: **unknown** (missing OCI revision labels)")

            old_repo = github_repo_from_source(old_meta.get("source"))
            new_repo = github_repo_from_source(new_meta.get("source"))
            compare_repo = None
            compare_repo_source = ""
            if old_repo and new_repo and old_repo == new_repo:
                compare_repo = old_repo
                compare_repo_source = "oci-source-label"
            elif old_repo and not new_repo:
                compare_repo = old_repo
                compare_repo_source = "oci-source-label-old"
            elif new_repo and not old_repo:
                compare_repo = new_repo
                compare_repo_source = "oci-source-label-new"
            elif old_repo and new_repo and old_repo != new_repo:
                lines.append(f"- Root repo mismatch between old/new labels: `{old_repo}` vs `{new_repo}`")
            if not compare_repo:
                guessed = guess_repo_from_image(change["repository"])
                if guessed:
                    compare_repo = guessed
                    compare_repo_source = "image-repo-heuristic"

            compare = fetch_github_compare(compare_repo, old_rev, new_rev)
            compare["repo_source"] = compare_repo_source or None

            lines.append(f"- Root repo for commit compare: `{short(compare_repo)}` (source: `{short(compare_repo_source or 'none')}`)")
            if compare.get("html_url"):
                lines.append(f"- Commit compare URL: {compare['html_url']}")
            if compare.get("total_commits") is not None:
                lines.append(
                    f"- Compare summary: status={short(compare.get('status'))}, total_commits={short(compare.get('total_commits'))}, ahead_by={short(compare.get('ahead_by'))}, behind_by={short(compare.get('behind_by'))}"
                )
            elif compare.get("error"):
                lines.append(f"- Compare lookup: **unavailable** ({short(compare.get('error'))})")

            commits = compare.get("commits") or []
            if commits:
                lines.append("- Commits between old/new revision:")
                for c in commits:
                    lines.append(f"  - `{short(c.get('sha'))}` {short(c.get('message'))}")

            files = compare.get("files") or []
            if files:
                lines.append("- Changed files in root repo compare (first 20):")
                for f in files:
                    lines.append(
                        f"  - `{short(f.get('filename'))}` status={short(f.get('status'))} changes={short(f.get('changes'))}"
                    )

            lines.append("- Old digest metadata:")
            lines.append("```json")
            lines.append(json.dumps(old_meta, indent=2))
            lines.append("```")
            lines.append("- New digest metadata:")
            lines.append("```json")
            lines.append(json.dumps(new_meta, indent=2))
            lines.append("```")
            lines.append("")

    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

if __name__ == "__main__":
    main()
