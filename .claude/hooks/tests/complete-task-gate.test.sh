#!/usr/bin/env bash
# Regression coverage for complete-task-gate.sh: it must block `git commit`
# until a pipeline-pass marker exists for the exact current working-tree
# state, and re-block the moment the tree changes again after the marker was
# written. Runs against an isolated scratch git repo, not this repo itself.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${DIR}/../tools/complete-task-gate.sh"
MARK_PASSED="${DIR}/../tools/complete-task-mark-passed.sh"
# shellcheck source=./test-helpers.sh
source "${DIR}/test-helpers.sh"

echo "complete-task-gate.sh"

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

(
  cd "$WORKDIR" || exit 1
  git init -q
  git config user.email "test@example.com"
  git config user.name "test"
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"
)

run_hook_commit() {
  echo '{"tool_input":{"command":"git commit -m test"}}' | (cd "$WORKDIR" && "$HOOK")
}

OUT=$(run_hook_commit 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "blocks commit with no pipeline-pass marker on record"

(cd "$WORKDIR" && echo "world" >> file.txt)
(cd "$WORKDIR" && bash "$MARK_PASSED" >/dev/null)

OUT=$(run_hook_commit 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "allows commit once the marker matches the exact current tree"

(cd "$WORKDIR" && echo "one more edit after marking" >> file.txt)

OUT=$(run_hook_commit 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "re-blocks after the tree changes again post-marker"

OUT=$(echo '{"tool_input":{"command":"git status"}}' | (cd "$WORKDIR" && "$HOOK") 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "does not interfere with a non-commit git command"

report_and_exit
