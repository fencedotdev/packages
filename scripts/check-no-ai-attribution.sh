#!/usr/bin/env bash
# Mechanized backstop for CLAUDE.md's non-negotiable "no AI attribution in
# commits or PRs" rule — added 2026-09-21 after the rule was violated twice
# in one desnarl/web + crossrepo-graph session despite being explicit and in
# context both times. Fails if any commit in the given git revision range
# contains AI-tool attribution in its message.
#
# Patterns matched, case-insensitive: a "Co-Authored-By:" trailer naming
# Claude, "Generated with ... Claude Code", or an @anthropic.com address
# (the strongest, lowest-false-positive signal, since it's not a word a
# human commit would plausibly contain for any other reason).

set -euo pipefail

RANGE="${1:?usage: check-no-ai-attribution.sh <git-rev-range>}"

PATTERN='(co-authored-by:.*claude|generated with.*claude code|anthropic\.com)'

FOUND=0
while IFS= read -r sha; do
  [ -z "$sha" ] && continue
  msg=$(git log -1 --format=%B "$sha" 2>/dev/null || true)
  if printf '%s' "$msg" | grep -qiE "$PATTERN"; then
    echo "::error::Commit ${sha} contains AI-tool attribution, which is not allowed in this repo (see CLAUDE.md):"
    printf '%s\n' "$msg" | grep -iE "$PATTERN" || true
    FOUND=1
  fi
done < <(git log --format=%H "$RANGE" 2>/dev/null || true)

if [ "$FOUND" -eq 1 ]; then
  echo "One or more commits contain AI-tool attribution. Amend/rewrite them (and force-push if already pushed) before this can merge." >&2
  exit 1
fi

echo "No AI-tool attribution found in ${RANGE}."
