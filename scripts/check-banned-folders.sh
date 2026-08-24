#!/usr/bin/env bash
# Mechanizes the banned-folder-name half of
# .claude/automatic-code-review/rules.md's Rule 3 — a literal name match,
# not a judgment call, so it belongs here rather than costing a
# (Haiku-model) automatic-code-reviewer call every session. The rest of
# Rule 3 ("does this name express a domain concept", e.g. is
# `envelopeService` fine but `service` alone isn't) stays with the LLM
# reviewer — that part genuinely isn't mechanizable.
#
# Adapted from repo-template's version for this repo's actual layout: an
# npm workspaces monorepo (package.json "workspaces": ["packages/*"]) with
# no top-level src/ at all — source lives under packages/*/src/. The
# template's `find src -type d ...` would silently match nothing here and
# always report clean, which is worse than no check at all.

set -euo pipefail

BANNED_NAMES=(utils helpers common shared core)
FOUND=0

for name in "${BANNED_NAMES[@]}"; do
  while IFS= read -r -d '' dir; do
    echo "Banned folder name: ${dir} (matches '${name}' — CLAUDE.md: everything gets a domain-specific home)"
    FOUND=1
  done < <(find packages/*/src -type d -name "$name" -print0 2>/dev/null)
done

if [ "$FOUND" -eq 1 ]; then
  exit 1
fi

echo "No banned folder names found under packages/*/src/."
exit 0
