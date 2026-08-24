#!/usr/bin/env bash
# Mechanizes a backstop for .claude/automatic-code-review/rules.md's Rule 4
# (no payment-shaped fields outside a repo explicitly scoped for them) —
# greps *newly added lines* in files changed since a base ref for the
# payment-shaped keyword patterns Rule 4 already names. Catches the
# obvious, unambiguous cases mechanically; does not replace
# automatic-code-reviewer's judgment on ambiguous ones (e.g. whether a
# generic `value` field is actually payment-shaped in context) — that
# nuance stays with the LLM reviewer.
#
# Scoped to added lines only (git diff's own `+` lines), not a whole-file
# scan — a whole-file scan re-flags every already-reviewed, accepted match
# in a file (e.g. checklist 4.1.15's own provisional-default `amount`
# field) on any later PR that merely touches that file for an unrelated
# reason, which would hard-fail CI on work that introduces nothing new.
# Found live, 2026-08-24: verify/route.ts's pre-existing, already-reviewed
# readPlatformFloorThreshold() re-triggered this the first time any PR
# touched that file after this check was wired into CI.

set -euo pipefail

BASE_REF="${1:-HEAD~1}"

# Case-insensitive; \b is GNU/BSD-grep-compatible via grep -E.
PATTERNS='\b(amount|card_?number|cardNumber|wallet_?address|walletAddress|payment_?method|paymentMethod)\b'

CHANGED_FILES=$(git diff --name-only "$BASE_REF" -- '*.ts' '*.tsx' '*.sql' 2>/dev/null || true)

if [ -z "$CHANGED_FILES" ]; then
  echo "No changed TypeScript/SQL files to check against ${BASE_REF}."
  exit 0
fi

FOUND=0
while IFS= read -r file; do
  [ -f "$file" ] || continue
  ADDED_LINES=$(git diff "$BASE_REF" -- "$file" | grep -E '^\+[^+]' | sed 's/^+//' || true)
  MATCHES=$(printf '%s\n' "$ADDED_LINES" | grep -nEi "$PATTERNS" || true)
  if [ -n "$MATCHES" ]; then
    echo "Possible payment-shaped field in ${file} (Rule 4 — no payment fields outside a repo explicitly scoped for them):"
    echo "$MATCHES" | sed 's/^/  /'
    FOUND=1
  fi
done <<< "$CHANGED_FILES"

if [ "$FOUND" -eq 1 ]; then
  echo ""
  echo "If this is a legitimate use (e.g. already covered by the brief's Prong 2 scoping), confirm with the founder before merging — this is a mechanical backstop, not a final judgment."
  exit 1
fi

echo "No payment-shaped field patterns found in changed files."
exit 0
