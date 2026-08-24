#!/usr/bin/env bash
# Records that the full verification pipeline (typecheck+lint+test+build+
# automatic-code-reviewer+task-check) has passed against the CURRENT working
# tree. Run only as the last step of /complete-task, once everything is
# clean. Keyed on tree content, not session ID, so any further edit made
# after this point invalidates the marker again automatically.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

HASH=$( { git status --porcelain=v1 -uall; git diff HEAD; } | shasum -a 256 | cut -d' ' -f1)
echo "$HASH" > .git/.fence-complete-task-passed
echo "Recorded pipeline pass for tree hash ${HASH:0:12}"
