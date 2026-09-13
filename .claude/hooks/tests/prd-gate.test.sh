#!/usr/bin/env bash
# Coverage for prd-gate.sh's mark-passed telemetry: it must append a durable
# line to internal/audits/pipeline-metrics.jsonl for any verdict (not just
# READY), record the attempt number, ignore calls for other subagent types,
# and degrade gracefully (no error) when there's no sibling internal/
# checkout to write into.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${DIR}/../tools/prd-gate.sh"
# shellcheck source=./test-helpers.sh
source "${DIR}/test-helpers.sh"

echo "prd-gate.sh"

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "${WORKDIR}/internal"
mkdir -p "${WORKDIR}/some-repo"
(
  cd "${WORKDIR}/some-repo" || exit 1
  git init -q
  git config user.email "t@t.com"
  git config user.name "t"
  git commit -q --allow-empty -m init
)

METRICS_FILE="${WORKDIR}/internal/audits/pipeline-metrics.jsonl"
TEST_SESSION_ID="test-session-$$"
SESSION_LOG="/tmp/fence-prdgate-log-${TEST_SESSION_ID}.jsonl"
rm -f "$SESSION_LOG"

payload_for() {
  local subagent="$1" report="$2"
  python3 -c "
import json, sys
print(json.dumps({
  'session_id': '${TEST_SESSION_ID}',
  'hook_event_name': 'SubagentStop',
  'agent_type': sys.argv[1],
  'last_assistant_message': sys.argv[2],
}))
" "$subagent" "$report"
}

READY_REPORT='## PRD-GATE REPORT

### GATE
READY

### ATTEMPT
1

### CONTEXT
- Task reference: fence-checklist-phase-1.md, item 1.5.3'

PAYLOAD=$(payload_for "prd-gate" "$READY_REPORT")
OUT=$(echo "$PAYLOAD" | (cd "${WORKDIR}/some-repo" && "$HOOK" mark-passed) 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "mark-passed exits 0 on a well-formed prd-gate report"

if [ -f "$METRICS_FILE" ] && grep -q '"verdict": "READY"' "$METRICS_FILE"; then
  echo "  ok: appends a durable READY line to pipeline-metrics.jsonl"
else
  echo "  FAIL: expected a READY line in ${METRICS_FILE}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q '"attempt": "1"' "$METRICS_FILE"; then
  echo "  ok: records the attempt number"
else
  echo "  FAIL: expected attempt=1 to be recorded"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q '"task_ref": "fence-checklist-phase-1.md, item 1.5.3"' "$METRICS_FILE"; then
  echo "  ok: records the task reference"
else
  echo "  FAIL: expected the task reference to be recorded"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Regression test: the report template puts "### GATE" and the verdict on
# separate lines, not "GATE: READY" on one — a real pre-existing bug meant
# gate_passed was never actually recorded against genuine multi-line output.
if grep -q '"event":"gate_passed"' "$SESSION_LOG" 2>/dev/null; then
  echo "  ok: records gate_passed against the real multi-line GATE/verdict format"
else
  echo "  FAIL: gate_passed was not recorded (regression of the GATE/verdict same-line-vs-separate-line bug)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

BLOCKED_REPORT='## PRD-GATE REPORT

### GATE
BLOCKED

### ATTEMPT
2

### CONTEXT
- Task reference: test item'

PAYLOAD_BLOCKED=$(payload_for "prd-gate" "$BLOCKED_REPORT")
echo "$PAYLOAD_BLOCKED" | (cd "${WORKDIR}/some-repo" && "$HOOK" mark-passed) > /dev/null 2>&1

if grep -q '"verdict": "BLOCKED"' "$METRICS_FILE"; then
  echo "  ok: also records a BLOCKED verdict, not just READY"
else
  echo "  FAIL: expected a BLOCKED line to be recorded too"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

LINES_BEFORE=$(wc -l < "$METRICS_FILE")
OTHER_PAYLOAD=$(payload_for "task-check" "irrelevant")
echo "$OTHER_PAYLOAD" | (cd "${WORKDIR}/some-repo" && "$HOOK" mark-passed) > /dev/null 2>&1
LINES_AFTER=$(wc -l < "$METRICS_FILE")
assert_exit_code "$LINES_BEFORE" "$LINES_AFTER" "ignores a mark-passed call for a different subagent_type"

NOINTERNAL_DIR=$(mktemp -d)
mkdir -p "${NOINTERNAL_DIR}/no-internal-repo"
(
  cd "${NOINTERNAL_DIR}/no-internal-repo" || exit 1
  git init -q
  git config user.email "t@t.com"
  git config user.name "t"
  git commit -q --allow-empty -m init
)
OUT=$(echo "$PAYLOAD" | (cd "${NOINTERNAL_DIR}/no-internal-repo" && "$HOOK" mark-passed) 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "does not error when no sibling internal/ checkout exists"
rm -rf "$NOINTERNAL_DIR"
rm -f "$SESSION_LOG"

# Regression test: a real bug (fixed alongside this test) where invoking the
# hook from inside a linked worktree (e.g. plan-next.md's isolation:"worktree"
# forks) resolved repo_root via --show-toplevel to the worktree's own nested
# path, breaking the "internal/ is a sibling of repo_root" derivation and
# silently skipping the durable write for every worktree-run item.
# Nested under the repo's own .claude/worktrees/, matching plan-next.md's
# real layout — a worktree sibling of the repo itself would not reproduce
# the bug (its "cd repo_root/.." would coincidentally still land beside
# internal/ in this test's own directory layout).
WORKTREE_DIR="${WORKDIR}/some-repo/.claude/worktrees/prd-gate-wt-test"
(cd "${WORKDIR}/some-repo" && git worktree add -q -b prd-gate-wt-test "$WORKTREE_DIR") >/dev/null 2>&1

LINES_BEFORE_WT=$(wc -l < "$METRICS_FILE")
PAYLOAD_WT=$(payload_for "prd-gate" "$READY_REPORT")
OUT=$(echo "$PAYLOAD_WT" | (cd "$WORKTREE_DIR" && "$HOOK" mark-passed) 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "mark-passed exits 0 when invoked from inside a linked worktree"

LINES_AFTER_WT=$(wc -l < "$METRICS_FILE")
if [ "$LINES_AFTER_WT" -gt "$LINES_BEFORE_WT" ]; then
  echo "  ok: telemetry from inside a linked worktree still reaches the main checkout's sibling internal/ (not silently dropped)"
else
  echo "  FAIL: worktree-invoked mark-passed did not append to ${METRICS_FILE} (regression of the worktree path-resolution bug)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

if tail -1 "$METRICS_FILE" | grep -q '"repo": "some-repo"'; then
  echo "  ok: repo name is derived from the main checkout, not the worktree's own directory name"
else
  echo "  FAIL: expected repo name 'some-repo' (main checkout basename), got a worktree-derived name instead"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

(cd "${WORKDIR}/some-repo" && git worktree remove -q --force "$WORKTREE_DIR") >/dev/null 2>&1 || true

report_and_exit
