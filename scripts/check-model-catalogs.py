#!/usr/bin/env python3
"""Fail when a client model catalog names a model litellm does not serve.

The served set is the union of two things, and using either alone is wrong:

  * `LiteLLMModel` CRs under litellm/models/ -- their `spec.modelName`.
  * llmkube `InferenceService` resources. The litellm-operator projects each
    Ready one into a `LiteLLMModel` named after the InferenceService, so those
    groups are real but exist nowhere in git as a CR. Checking against the CRs
    alone reports every `llama-*` reference as stale.

Deriving projections from the InferenceService names rather than the cluster
keeps this runnable offline, and errs safe: git holds a superset of what is
Ready, so the check cannot invent a stale reference.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
LLM = ROOT / "kubernetes/apps/base/llm"


def docs(path: Path, strict: bool = False):
    """Yield the mapping documents in a YAML file.

    With strict=True the file is required to parse and to contain at least one
    mapping; a truncated or emptied manifest would otherwise contribute zero
    references and let the check pass while the file is broken. The tree-wide
    InferenceService sweep stays lenient, since it legitimately encounters
    list-valued YAML it does not care about.
    """
    try:
        loaded = list(yaml.safe_load_all(path.read_text()))
    except yaml.YAMLError as exc:
        if not strict:
            return
        print(f"{path}: not parseable as YAML -- {exc}", file=sys.stderr)
        raise SystemExit(2)
    if strict and not any(isinstance(d, dict) for d in loaded):
        print(f"{path}: contains no YAML documents -- truncated or emptied?", file=sys.stderr)
        raise SystemExit(2)
    yield from (d for d in loaded if isinstance(d, dict))


def served() -> set[str]:
    names = set()
    for path in (LLM / "litellm/models").glob("*.yaml"):
        for doc in docs(path, strict=True):
            if doc.get("kind") == "LiteLLMModel":
                names.add(doc["spec"]["modelName"])
    for path in (ROOT / "kubernetes").rglob("*.yaml"):
        for doc in docs(path):
            if doc.get("kind") == "InferenceService":
                names.add(doc["metadata"]["name"])
    return names


def known(ref: str, names: set[str]) -> bool:
    """A reference may carry a provider prefix (`litellm/llama-strix`), and a
    served name may itself contain a slash (`chatgpt/gpt-5.6-sol`)."""
    return ref in names or ref.split("/", 1)[-1] in names


def refs_from_virtualkeys() -> list[tuple[str, str]]:
    out = []
    for path in (LLM / "litellm/virtualkeys").glob("*.yaml"):
        for doc in docs(path, strict=True):
            if doc.get("kind") == "LiteLLMVirtualKey":
                for m in doc["spec"].get("models", []):
                    out.append((f"virtualkey {path.stem}", m))
    return out


# Each configmap embeds a client's own config as a string, so the references are
# matched textually rather than parsed.
EMBEDDED = [
    ("opencode", LLM / "opencode/configmap.yaml", r'"model":\s*"([^"]+)"'),
    # Model entries are single-line and carry contextWindow; agent definitions
    # spread `id:` over several lines and would otherwise match.
    ("openclaw", LLM / "openclaw/app/configmap.yaml", r'^\s*\{ id: "([^"]+)".*contextWindow'),
    ("hermes", LLM / "hermes/configmap.yaml", r"^\s*model:\s*(\S+)\s*$"),
]


def main() -> int:
    names = served()
    if not names:
        print("no model definitions found -- has the layout moved?", file=sys.stderr)
        return 2

    refs = refs_from_virtualkeys()
    for label, path, pattern in EMBEDDED:
        if not path.exists():
            print(f"{label}: {path} is missing -- has the layout moved?", file=sys.stderr)
            return 2
        found = [m.group(1) for m in re.finditer(pattern, path.read_text(), re.MULTILINE)]
        if not found:
            print(f"{label}: matched no models -- has its config format changed?", file=sys.stderr)
            return 2
        refs.extend((label, ref) for ref in found)

    stale = sorted({(where, ref) for where, ref in refs if not known(ref, names)})
    if stale:
        print("Model references that litellm does not serve:\n", file=sys.stderr)
        for where, ref in stale:
            print(f"  {where}: {ref}", file=sys.stderr)
        print(
            f"\nServed groups ({len(names)}):\n  " + "  ".join(sorted(names)),
            file=sys.stderr,
        )
        return 1

    print(f"{len(refs)} references checked against {len(names)} served groups -- all resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
