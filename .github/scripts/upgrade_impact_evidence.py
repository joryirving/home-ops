#!/usr/bin/env python3
"""Evidence provider: upstream upgrade impact for version-bump PRs.

Emits the action's evidence-provider JSON contract on stdout:
  {"severity": "info", "findings": [{"severity","message","source"}]}

Detects chart bumps (ocirepository.yaml tag changes) and container image bumps
(helmrelease.yaml image tag changes) in the PR diff, injects the deployment's
HelmRelease values, and fetches upstream GitHub release notes for the bumped
version range via authenticated `gh api`. Complements konflate: konflate shows
what changes in rendered manifests; this shows what changed upstream so the
model can cross-reference release notes against the values this repo sets.

Reads PR_NUMBER (and optionally GITHUB_REPOSITORY) from the environment, set
by the action. Read-only, advisory, never a gate: on any failure or a
non-bump PR it emits an empty findings list and exits 0.
"""
import json
import os
import re
import subprocess
import sys

PR = os.environ.get("PR_NUMBER", "").strip()
REPO = os.environ.get("GITHUB_REPOSITORY", "").strip()

MAX_RELEASES = 4
MAX_NOTES_BYTES = 3500
MAX_VALUES_BYTES = 4000
MAX_TOTAL_BYTES = 19000

_FILE_RE = re.compile(r"^\+\+\+ b/(.+)$")
_TAG_RE = re.compile(r"^([-+ ])\s*tag: (\S+)")
_URL_RE = re.compile(r"^[-+ ]\s*url: oci://(\S+)")
_REPOSITORY_RE = re.compile(r"^[-+ ]\s*repository: (\S+)")


def _emit(findings, severity="info"):
    print(json.dumps({"severity": severity, "findings": findings}))
    sys.exit(0)


def _clean_tag(tag):
    return tag.split("@", 1)[0].strip().strip('"')


def parse_bumps(diff_text):
    """Extract version bumps from a unified PR diff.

    Returns [{"path","kind","artifact","old","new"}] where kind is "chart"
    (ocirepository.yaml) or "image" (helmrelease.yaml). artifact may be None
    when the identifying url/repository line is outside the hunk; main()
    falls back to reading the file from the checkout.
    """
    bumps = []
    path = None
    image_repo = None
    old_tag = None
    for line in diff_text.splitlines():
        m = _FILE_RE.match(line)
        if m:
            path = m.group(1)
            image_repo = old_tag = None
            continue
        if path is None or not path.startswith("kubernetes/"):
            continue
        is_oci = path.endswith("ocirepository.yaml")
        is_hr = path.endswith("helmrelease.yaml")
        if not (is_oci or is_hr):
            continue
        m = _URL_RE.match(line)
        if m:
            # In OCIRepository manifests url: follows ref.tag, so the tag
            # pair is usually recorded before the url line is seen.
            for b in bumps:
                if b["path"] == path and b["kind"] == "chart" and b["artifact"] is None:
                    b["artifact"] = m.group(1)
            continue
        m = _REPOSITORY_RE.match(line)
        if m:
            image_repo = m.group(1).strip('"')
            continue
        m = _TAG_RE.match(line)
        if not m:
            continue
        sign, tag = m.group(1), _clean_tag(m.group(2))
        if sign == "-":
            old_tag = tag
        elif sign == "+" and old_tag is not None:
            if tag != old_tag:
                bumps.append({
                    "path": path,
                    "kind": "chart" if is_oci else "image",
                    "artifact": None if is_oci else image_repo,
                    "old": old_tag,
                    "new": tag,
                })
            old_tag = None
    return bumps


def parse_version(text):
    m = re.search(r"\d+(?:\.\d+)+", text or "")
    if not m:
        return None
    return tuple(int(p) for p in m.group(0).split("."))


def select_releases(releases, old, new):
    """Releases with version in (old, new], newest first, capped.

    Returns (selected, omitted_count). Unparseable `old` widens the lower
    bound; unparseable `new` selects nothing (can't bound the range).
    """
    lo, hi = parse_version(old), parse_version(new)
    if hi is None:
        return [], 0
    picked = []
    for r in releases:
        if r.get("draft") or r.get("prerelease"):
            continue
        v = parse_version(r.get("tag_name", ""))
        if v is None or v > hi:
            continue
        if lo is not None and v <= lo:
            continue
        picked.append((v, r))
    picked.sort(key=lambda t: t[0], reverse=True)
    return [r for _, r in picked[:MAX_RELEASES]], max(0, len(picked) - MAX_RELEASES)
