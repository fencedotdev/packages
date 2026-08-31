#!/usr/bin/env bash
# Locks the failing test file(s) test-author writes, so the implementation
# step (GREEN, then refactor) can't silently rewrite the spec it's meant to
# satisfy — the structural guardrail behind the AI Refinement Method's Test
# Author/Implementer split.
#
# `lock` mode (SubagentStop): watches for a finished subagent whose
# agent_type is "test-author" and whose report says STATUS: DONE, parses
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
#
# `lock` mode was originally wired to PostToolUse on the dispatch tool
# itself, reading subagent_type/tool_response from that event's payload —
# this silently never fired for an async/background dispatch, since
# PostToolUse for an async call only ever sees the launch acknowledgment
# ({"isAsync": true, "status": "async_launched", ...}), never the real
# completed report. Confirmed via direct instrumentation, 2026-08-30 (see
# fencedotdev/repo-template#38). SubagentStop is the correct event — it
# fires once the subagent has actually finished, with `agent_type` and
# `last_assistant_message` (the real report text) directly on the payload,
# no tool_response guessing needed.

set -euo pipefail

MODE="${1:-gate}"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || echo "")
[ -z "$SESSION_ID" ] && exit 0

LOCK_FILE="/tmp/fence-testlock-${SESSION_ID}.jsonl"

# Normalizes a path to repo-relative form before it's ever stored or
# compared. A real Edit/Write tool call's file_path is always absolute (the
# Edit tool's own spec requires it), but test-author's own report template
# locks a relative-looking path with no instruction to use an absolute one
# - so without this, the exact-string match in gate mode below would never
# fire for a real Edit/Write call, in any session, forked or not. This also
# makes the lock survive a worktree handoff (test-author locking a file in
# one worktree, implementation editing it in a different one): each side
# strips its OWN git root at the moment it runs, so both always resolve to
# the same repo-relative suffix regardless of which absolute worktree path
# either one started from. Falls back to the original string unchanged if a
# git root can't be determined, or the path isn't under it - never silently
# drops a lock, only ever normalizes one.
normalize_path() {
  local raw="$1"
  python3 -c "
import subprocess, sys, os
raw = sys.argv[1]
if not raw or not os.path.isabs(raw):
    print(raw)
else:
    try:
        root = subprocess.check_output(
            ['git', 'rev-parse', '--show-toplevel'],
            text=True, stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        print(raw)
        sys.exit(0)
    if raw.startswith(root + '/'):
        print(raw[len(root) + 1:])
    else:
        print(raw)
" "$raw"
}

if [ "$MODE" = "lock" ]; then
  SUBAGENT=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('agent_type',''))
" 2>/dev/null || echo "")
  [ "$SUBAGENT" != "test-author" ] && exit 0

  OUTPUT_TEXT=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('last_assistant_message',''))
" 2>/dev/null || echo "")

  STATUS=$(echo "$OUTPUT_TEXT" | grep -A1 "^### STATUS" | tail -1 | grep -oE "DONE|BLOCKED|NEED_INFO" | head -1)
  [ "$STATUS" != "DONE" ] && exit 0

  # Everything between "### LOCKED FILES" and the next "###" header, as
  # "- path" bullet lines.
  LOCKED_PATHS=$(echo "$OUTPUT_TEXT" | awk '/^### LOCKED FILES/{f=1;next} /^###/{f=0} f' | grep -oE '^- .+' | sed -E 's/^- //')

  while IFS= read -r path; do
    [ -z "$path" ] && continue
    NORM_PATH=$(normalize_path "$path")
    echo "{\"event\":\"locked\",\"file\":\"${NORM_PATH}\",\"ts\":$(date +%s)}" >> "$LOCK_FILE"
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
FILE_PATH=$(normalize_path "$FILE_PATH")

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
