#!/usr/bin/env bash
# Locks the failing test file(s) test-author writes, so the implementation
# step (GREEN, then refactor) can't silently rewrite the spec it's meant to
# satisfy — the structural guardrail behind the AI Refinement Method's Test
# Author/Implementer split.
#
# `lock` mode (PostToolUse on Task): watches for a completed
# subagent_type "test-author" call whose report says STATUS: DONE, parses
# its LOCKED FILES list, and records each path as locked for this session.
# `gate` mode (PreToolUse on Edit|Write): blocks any write to a locked path.
# Capped, not an unconditional hard block — a buggy lock must not be able to
# silently hang an unattended /run-task fork. After 3 blocked attempts on
# the same session, the 4th returns a terminal "stop and ask the user"
# instruction instead of just blocking again, same escalation discipline as
# prd-gate/task-check's 3-attempt cap. Only matches Edit|Write — an agent
# could still route around this via Bash; the backstop there is
# repo-template/CLAUDE.md's cultural norm against tool-routing around a
# block, not a technical guarantee (see this repo's CLAUDE.md Security
# section: "a sandbox-blocked action is a stop signal, not an obstacle").

set -euo pipefail

MODE="${1:-gate}"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || echo "")
[ -z "$SESSION_ID" ] && exit 0

LOCK_FILE="/tmp/fence-testlock-${SESSION_ID}.jsonl"

if [ "$MODE" = "lock" ]; then
  SUBAGENT=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('tool_input',{}).get('subagent_type',''))
" 2>/dev/null || echo "")
  [ "$SUBAGENT" != "test-author" ] && exit 0

  OUTPUT_TEXT=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
r=d.get('tool_response', d.get('tool_result',''))
if isinstance(r, dict):
  print(r.get('content', r.get('output', r.get('text', json.dumps(r)))))
else:
  print(r)
" 2>/dev/null || echo "")

  STATUS=$(echo "$OUTPUT_TEXT" | grep -A1 "^### STATUS" | tail -1 | grep -oE "DONE|BLOCKED|NEED_INFO" | head -1)
  [ "$STATUS" != "DONE" ] && exit 0

  # Everything between "### LOCKED FILES" and the next "###" header, as
  # "- path" bullet lines.
  LOCKED_PATHS=$(echo "$OUTPUT_TEXT" | awk '/^### LOCKED FILES/{f=1;next} /^###/{f=0} f' | grep -oE '^- .+' | sed -E 's/^- //')

  while IFS= read -r path; do
    [ -z "$path" ] && continue
    echo "{\"event\":\"locked\",\"file\":\"${path}\",\"ts\":$(date +%s)}" >> "$LOCK_FILE"
  done <<< "$LOCKED_PATHS"

  exit 0
fi

# gate mode
[ ! -f "$LOCK_FILE" ] && exit 0

FILE_PATH=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
inp=d.get('tool_input',{})
print(inp.get('file_path', inp.get('path', '')))
" 2>/dev/null || echo "")
[ -z "$FILE_PATH" ] && exit 0

IS_LOCKED=$(python3 -c "
import json
target = '''${FILE_PATH}'''
try:
  with open('${LOCK_FILE}') as f:
    for line in f:
      try:
        d = json.loads(line.strip())
      except Exception:
        continue
      if d.get('event') == 'locked' and d.get('file') == target:
        print('true')
        break
except FileNotFoundError:
  pass
" 2>/dev/null || echo "")

[ "$IS_LOCKED" != "true" ] && exit 0

BLOCKED_COUNT=$(grep -c "\"event\":\"blocked\",\"file\":\"${FILE_PATH}\"" "$LOCK_FILE" 2>/dev/null || echo "0")
NEXT_COUNT=$((BLOCKED_COUNT + 1))
echo "{\"event\":\"blocked\",\"file\":\"${FILE_PATH}\",\"ts\":$(date +%s)}" >> "$LOCK_FILE"

if [ "$NEXT_COUNT" -ge 4 ]; then
  echo "Blocked: ${FILE_PATH} is a locked test-author spec, and this is the 4th attempt to edit it this session. STOP — do not try another tool or approach to edit it. If you believe this test is genuinely wrong, tell the user exactly why and ask; do not keep retrying." >&2
  exit 1
fi

echo "Blocked: ${FILE_PATH} is a locked test-author spec (attempt ${NEXT_COUNT}/3 before this escalates). If the test itself seems wrong, stop and ask the user rather than editing around the lock — a coverage gap belongs in a new test file, not an edit to this one." >&2
exit 1
