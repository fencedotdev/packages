#!/usr/bin/env bash
# Coverage for task-check.sh's `record` mode: it must append a durable line
# to internal/audits/pipeline-metrics.jsonl for any verdict (PASS/FAIL/
# NEED_INFO), record the attempt number, ignore calls for other subagent
# types, and degrade gracefully with no sibling internal/ checkout.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${DIR}/../tools/task-check.sh"
# shellcheck source=./test-helpers.sh
source "${DIR}/test-helpers.sh"

echo "task-check.sh record mode"

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

payload_for() {
  local subagent="$1" report="$2"
  python3 -c "
import json, sys
print(json.dumps({
  'session_id': 'test-session',
  'hook_event_name': 'SubagentStop',
  'agent_type': sys.argv[1],
  'last_assistant_message': sys.argv[2],
}))
" "$subagent" "$report"
}

PASS_REPORT='## TASK CHECK REPORT

### STATUS
PASS

### ATTEMPT
1

### CONTEXT
- Task reference: fence-checklist-phase-1.md, item 1.5.3'

PAYLOAD=$(payload_for "task-check" "$PASS_REPORT")
OUT=$(echo "$PAYLOAD" | (cd "${WORKDIR}/some-repo" && "$HOOK" record) 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "record exits 0 on a well-formed task-check report"

if [ -f "$METRICS_FILE" ] && grep -q '"verdict": "PASS"' "$METRICS_FILE"; then
  echo "  ok: appends a durable PASS line to pipeline-metrics.jsonl"
else
  echo "  FAIL: expected a PASS line in ${METRICS_FILE}"
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

FAIL_REPORT='## TASK CHECK REPORT

### STATUS
FAIL

### ATTEMPT
2

### CONTEXT
- Task reference: test item'

PAYLOAD_FAIL=$(payload_for "task-check" "$FAIL_REPORT")
echo "$PAYLOAD_FAIL" | (cd "${WORKDIR}/some-repo" && "$HOOK" record) > /dev/null 2>&1

if grep -q '"verdict": "FAIL"' "$METRICS_FILE"; then
  echo "  ok: also records a FAIL verdict, not just PASS"
else
  echo "  FAIL: expected a FAIL line to be recorded too"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

LINES_BEFORE=$(wc -l < "$METRICS_FILE")
OTHER_PAYLOAD=$(payload_for "prd-gate" "irrelevant")
echo "$OTHER_PAYLOAD" | (cd "${WORKDIR}/some-repo" && "$HOOK" record) > /dev/null 2>&1
LINES_AFTER=$(wc -l < "$METRICS_FILE")
assert_exit_code "$LINES_BEFORE" "$LINES_AFTER" "ignores a record call for a different subagent_type"

NOINTERNAL_DIR=$(mktemp -d)
mkdir -p "${NOINTERNAL_DIR}/no-internal-repo"
(
  cd "${NOINTERNAL_DIR}/no-internal-repo" || exit 1
  git init -q
  git config user.email "t@t.com"
  git config user.name "t"
  git commit -q --allow-empty -m init
)
OUT=$(echo "$PAYLOAD" | (cd "${NOINTERNAL_DIR}/no-internal-repo" && "$HOOK" record) 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "does not error when no sibling internal/ checkout exists"
rm -rf "$NOINTERNAL_DIR"

report_and_exit
