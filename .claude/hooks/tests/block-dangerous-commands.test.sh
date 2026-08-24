#!/usr/bin/env bash
# Regression coverage for block-dangerous-commands.sh. Written specifically
# because this hook already shipped one real bug in production: on BSD grep
# (macOS's default), a pattern starting with "--" (e.g. --no-verify) was
# parsed as an unrecognized flag rather than a literal string, so the match
# silently never fired and the exact command this hook exists to block was
# let through unblocked. Fixed with `grep -q -- "$pattern"`; this test file
# exists so that fix can never silently regress.
#
# Also covers the later Edit/Write/MultiEdit branch (added alongside
# continue-task-sweep.yml): it must stay a no-op unless
# FENCE_CONTINUE_TASK_SWEEP=true is set, so it can never block a normal
# interactive session's legitimate pipeline-development edits.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${DIR}/../tools/block-dangerous-commands.sh"
# shellcheck source=./test-helpers.sh
source "${DIR}/test-helpers.sh"

run_hook() {
  local command="$1"
  local payload
  payload=$(python3 -c "import json,sys; print(json.dumps({'tool_name': 'Bash', 'tool_input': {'command': sys.argv[1]}}))" "$command")
  echo "$payload" | "$HOOK"
}

run_edit_hook() {
  local file_path="$1" tool_name="${2:-Edit}"
  local payload
  payload=$(python3 -c "import json,sys; print(json.dumps({'tool_name': sys.argv[1], 'tool_input': {'file_path': sys.argv[2]}}))" "$tool_name" "$file_path")
  echo "$payload" | "$HOOK"
}

echo "block-dangerous-commands.sh"

OUT=$(run_hook "git commit --no-verify -m test" 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "blocks git commit --no-verify (the BSD-grep regression case)"
assert_contains "$OUT" "no-verify" "reports which pattern matched"

OUT=$(run_hook "git push --force" 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "blocks git push --force"

OUT=$(run_hook "git push -f origin main" 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "blocks git push -f"

OUT=$(run_hook "git reset --hard HEAD~1" 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "blocks git reset --hard"

OUT=$(run_hook "git branch -D some-branch" 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "blocks git branch -D"

OUT=$(run_hook "git status" 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "allows an ordinary git status"

OUT=$(run_hook "git commit -m 'add a feature'" 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "allows an ordinary git commit"

OUT=$(run_hook "cat .github/workflows/ci.yml" 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "blocks a command touching a protected config path (.github/workflows)"

unset FENCE_CONTINUE_TASK_SWEEP
OUT=$(run_edit_hook ".claude/settings.json" 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "does NOT block a normal interactive Edit to .claude/ (FENCE_CONTINUE_TASK_SWEEP unset)"

OUT=$(run_edit_hook "src/widgets/widget.ts" 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "allows an ordinary Edit to a non-protected file, sweep context or not"

export FENCE_CONTINUE_TASK_SWEEP=true
OUT=$(run_edit_hook ".claude/settings.json" 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "blocks an Edit to .claude/ when FENCE_CONTINUE_TASK_SWEEP=true (the sweep context)"

OUT=$(run_edit_hook "package.json" "Write" 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "blocks a Write to package.json in the sweep context"

OUT=$(run_edit_hook ".github/workflows/ci.yml" "MultiEdit" 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "blocks a MultiEdit to .github/workflows/ in the sweep context"

OUT=$(run_edit_hook "src/widgets/widget.ts" 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "still allows an ordinary Edit to a non-protected file in the sweep context"
unset FENCE_CONTINUE_TASK_SWEEP

report_and_exit
