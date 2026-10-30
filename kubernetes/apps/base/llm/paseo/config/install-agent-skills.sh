#!/usr/bin/env bash
set -euo pipefail

# Home is an existing PVC. Stage the read-only skill on each pod start so
# updates survive rolling deployments without changing the Paseo image.
: "$${HOME:?HOME must be set}"
mkdir -p "$${HOME}/.agents/skills/simple-english/references"
install -m 0644 /etc/agent-skills/simple-english/SKILL.md "$${HOME}/.agents/skills/simple-english/SKILL.md"
for ref in rule-catalog strict-vocabulary use-cases word-swaps; do
  install -m 0644 "/etc/agent-skills/simple-english/$${ref}.md" "$${HOME}/.agents/skills/simple-english/references/$${ref}.md"
done

exec /usr/local/bin/paseo-start
