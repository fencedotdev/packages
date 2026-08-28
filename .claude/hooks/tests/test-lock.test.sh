#!/usr/bin/env bash
# Coverage for test-lock.sh: it must lock exactly the files test-author's
# LOCKED FILES list names, block Edit/Write attempts on locked paths, leave
# unlocked paths alone, and escalate (distinct message, still blocked) on
# the 4th blocked attempt rather than looping forever.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${DIR}/../tools/test-lock.sh"
# shellcheck source=./test-helpers.sh
source "${DIR}/test-helpers.sh"

echo "test-lock.sh"

SESSION_ID="test-lock-session-$$"
LOCK_FILE="/tmp/fence-testlock-${SESSION_ID}.jsonl"
rm -f "$LOCK_FILE"

lock_payload() {
  local report="$1"
  python3 -c "
import json, sys
print(json.dumps({
  'session_id': '${SESSION_ID}',
  'tool_input': {'subagent_type': 'test-author'},
  'tool_response': sys.argv[1],
}))
" "$report"
}

gate_payload() {
  local file_path="$1"
  python3 -c "
import json, sys
print(json.dumps({
  'session_id': '${SESSION_ID}',
  'tool_input': {'file_path': sys.argv[1]},
}))
" "$file_path"
}

DONE_REPORT='## TEST-AUTHOR REPORT

### STATUS
DONE

### ATTEMPT
1

### CONTEXT
- Task reference: test item

### SPEC SUMMARY
covers the happy path

### LOCKED FILES
- src/widgets/__tests__/widget.test.ts
- src/widgets/__tests__/widget-edge-cases.test.ts

### RED CONFIRMED
yes'

PAYLOAD=$(lock_payload "$DONE_REPORT")
OUT=$(echo "$PAYLOAD" | "$HOOK" lock 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "lock mode exits 0 on a well-formed DONE report"

if grep -q '"file":"src/widgets/__tests__/widget.test.ts"' "$LOCK_FILE"; then
  echo "  ok: locks the first listed file"
else
  echo "  FAIL: expected widget.test.ts to be locked"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q '"file":"src/widgets/__tests__/widget-edge-cases.test.ts"' "$LOCK_FILE"; then
  echo "  ok: locks the second listed file"
else
  echo "  FAIL: expected widget-edge-cases.test.ts to be locked"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

OUT=$(echo "$(gate_payload "src/widgets/__tests__/widget.test.ts")" | "$HOOK" gate 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "gate mode blocks an edit to a locked file"

OUT=$(echo "$(gate_payload "src/widgets/widget.ts")" | "$HOOK" gate 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "gate mode allows an edit to an unlocked file (the implementation itself)"

OUT=$(echo "$(gate_payload "src/widgets/__tests__/widget-new-case.test.ts")" | "$HOOK" gate 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "gate mode allows a NEW test file that was never locked (the coverage-gap escape valve)"

# Drive the same locked file to its 4th blocked attempt and confirm the
# message escalates while still blocking (never silently unlocks).
"$HOOK" gate < <(gate_payload "src/widgets/__tests__/widget.test.ts") > /dev/null 2>&1
"$HOOK" gate < <(gate_payload "src/widgets/__tests__/widget.test.ts") > /dev/null 2>&1
OUT=$(echo "$(gate_payload "src/widgets/__tests__/widget.test.ts")" | "$HOOK" gate 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "still blocks on the 4th attempt (never silently unlocks)"
assert_contains "$OUT" "STOP" "escalates to a stop-and-ask message on the 4th attempt"

DIFFERENT_SESSION_PAYLOAD=$(python3 -c "
import json
print(json.dumps({'session_id': 'a-totally-different-session', 'tool_input': {'file_path': 'src/widgets/__tests__/widget.test.ts'}}))
")
OUT=$(echo "$DIFFERENT_SESSION_PAYLOAD" | "$HOOK" gate 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "does not leak locks across sessions"

# Real-world path-format bug: test-author's own report template locks a
# repo-relative path (e.g. "src/foo.test.ts"), but a real Edit/Write tool
# call's file_path is always absolute (the Edit tool's own spec requires
# it) - so the exact-string match must normalize both sides to the same
# form or the block silently never fires, in any session, forked or not.
REPO_ROOT="$(git rev-parse --show-toplevel)"
ABSOLUTE_PATH="${REPO_ROOT}/src/widgets/__tests__/widget.test.ts"

OUT=$(echo "$(gate_payload "$ABSOLUTE_PATH")" | "$HOOK" gate 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "gate mode blocks an absolute-path edit to a file locked under its relative path"

# Defensive direction: lock mode itself should also normalize if it's ever
# handed an absolute path (a different session, so it doesn't collide with
# the locks already recorded above).
ABS_SESSION_ID="test-lock-abs-session-$$"
ABS_LOCK_FILE="/tmp/fence-testlock-${ABS_SESSION_ID}.jsonl"
rm -f "$ABS_LOCK_FILE"

ABS_LOCK_PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
  'session_id': '${ABS_SESSION_ID}',
  'tool_input': {'subagent_type': 'test-author'},
  'tool_response': sys.argv[1],
}))
" "## TEST-AUTHOR REPORT

### STATUS
DONE

### ATTEMPT
1

### CONTEXT
- Task reference: test item

### SPEC SUMMARY
covers the happy path

### LOCKED FILES
- ${ABSOLUTE_PATH}

### RED CONFIRMED
yes")

OUT=$(echo "$ABS_LOCK_PAYLOAD" | "$HOOK" lock 2>&1); EXIT=$?
assert_exit_code 0 "$EXIT" "lock mode exits 0 when the report hands it an absolute path"

ABS_GATE_PAYLOAD=$(python3 -c "
import json
print(json.dumps({'session_id': '${ABS_SESSION_ID}', 'tool_input': {'file_path': 'src/widgets/__tests__/widget.test.ts'}}))
")
OUT=$(echo "$ABS_GATE_PAYLOAD" | "$HOOK" gate 2>&1); EXIT=$?
assert_exit_code 1 "$EXIT" "gate mode blocks a relative-path edit to a file locked under its absolute path"

rm -f "$ABS_LOCK_FILE"
rm -f "$LOCK_FILE"

report_and_exit
