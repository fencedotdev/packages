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

# Narrow, auditable escape hatch — mirrors `verification`'s own
# check-payment-fields.sh precedent exactly (found live there 2026-08-24,
# ported here 2026-09-01 after sandbox hit the identical false positive on
# checklist 1.10.5's Action.value.amount, M·3's own generic value shape,
# not a settlement amount). ALLOW_MARKER_PREFIX is a prefix, not one fixed
# string, so each case states its own reason
# (payment-fields-check:allow-<why>) rather than reusing another case's —
# a reviewer can see, from the marker text alone, why a given line is
# suppressed. A line matching ONLY the `amount` keyword is skipped if it
# also carries a marker with this prefix; card/wallet/payment-method
# matches always hard-fail regardless of the marker, so this can never be
# used to wave through the patterns that matter most.
ALLOW_MARKER_PREFIX='payment-fields-check:allow-'
AMOUNT_ONLY_PATTERN='\bamount\b'
NEVER_SUPPRESSIBLE_PATTERNS='\b(card_?number|cardNumber|wallet_?address|walletAddress|payment_?method|paymentMethod)\b'

CHANGED_FILES=$(git diff --name-only "$BASE_REF" -- '*.ts' '*.tsx' '*.sql' 2>/dev/null || true)

if [ -z "$CHANGED_FILES" ]; then
  echo "No changed TypeScript/SQL files to check against ${BASE_REF}."
  exit 0
fi

FOUND=0
while IFS= read -r file; do
  [ -f "$file" ] || continue
  ADDED_LINES=$(git diff "$BASE_REF" -- "$file" | grep -E '^\+[^+]' | sed 's/^+//' || true)
  ALL_MATCHES=$(printf '%s\n' "$ADDED_LINES" | grep -nEi "$PATTERNS" || true)
  MATCHES=$(printf '%s\n' "$ALL_MATCHES" | while IFS= read -r matched_line; do
    [ -z "$matched_line" ] && continue
    if printf '%s\n' "$matched_line" | grep -qF "$ALLOW_MARKER_PREFIX" \
      && printf '%s\n' "$matched_line" | grep -qEi "$AMOUNT_ONLY_PATTERN" \
      && ! printf '%s\n' "$matched_line" | grep -qEi "$NEVER_SUPPRESSIBLE_PATTERNS"; then
      continue
    fi
    printf '%s\n' "$matched_line"
  done)
  if [ -n "$MATCHES" ]; then
    echo "Possible payment-shaped field in ${file} (Rule 4 — no payment fields outside a repo explicitly scoped for them):"
    echo "$MATCHES" | sed 's/^/  /'
    FOUND=1
  fi
done <<< "$CHANGED_FILES"

if [ "$FOUND" -eq 1 ]; then
  echo ""
  echo "If this is a legitimate use (e.g. already covered by the brief's Prong 2 scoping), confirm with the founder before merging — this is a mechanical backstop, not a final judgment. To record an approved exception for a genuine M·2/M·3 value shape, add a same-line trailing comment: // ${ALLOW_MARKER_PREFIX}<short-reason>"
  exit 1
fi

echo "No payment-shaped field patterns found in changed files."
exit 0
