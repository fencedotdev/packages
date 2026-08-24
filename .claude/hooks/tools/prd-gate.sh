#!/usr/bin/env bash
# PRD-gate hook for Fence repos.
# `gate` mode (PreToolUse on Write|Edit|MultiEdit): nags once per session,
# on the first product-code write, if the prd-gate subagent hasn't reported
# GATE: READY yet. Nags exactly once (soft, exit 2) — a broken marker should
# never permanently block writes, so any subsequent call in the same session
# passes silently once one nag has been issued.
# `mark-passed` mode (PostToolUse on Task): watches for a completed
# subagent_type "prd-gate" call whose output says GATE: READY, and records it.
# Also appends a durable telemetry line (verdict + attempt, whatever the
# verdict was) to internal/audits/pipeline-metrics.jsonl — closes posture.md's
# own self-flagged "NOT TRACKED" gap. Assumes the workspace sibling-checkout
# topology (this repo and internal/ as siblings); when that doesn't resolve
# (e.g. a single-repo CI checkout with no internal/ sibling — see
# continue-task-sweep.yml), skips the durable write with a warning rather
# than failing the hook.

set -euo pipefail

record_pipeline_metric() {
  # $1 event name, $2 verdict, $3 attempt, $4 task_ref (may be empty/unknown)
  local repo_root internal_dir repo_name
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
  [ -z "$repo_root" ] && return 0
  internal_dir="$(cd "${repo_root}/.." 2>/dev/null && pwd)/internal"
  if [ ! -d "$internal_dir" ]; then
    echo "prd-gate telemetry: no sibling internal/ checkout found — skipping durable log (expected outside the workspace sibling-checkout topology)." >&2
    return 0
  fi
  mkdir -p "${internal_dir}/audits"
  repo_name="$(basename "$repo_root")"
  python3 -c "
import json, sys, time
print(json.dumps({
  'ts': int(time.time()),
  'repo': sys.argv[1],
  'agent': 'prd-gate',
  'event': sys.argv[2],
  'verdict': sys.argv[3],
  'attempt': sys.argv[4],
  'task_ref': sys.argv[5],
}))
" "$repo_name" "$1" "$2" "$3" "$4" >> "${internal_dir}/audits/pipeline-metrics.jsonl" 2>/dev/null || true
}

MODE="${1:-gate}"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETTINGS_FILE="${PLUGIN_ROOT}/settings.json"

is_enabled() {
  python3 -c "
import json,sys
try:
  with open('${SETTINGS_FILE}') as f:
    d=json.load(f)
  print('true' if d.get('prdGate',{}).get('enabled',True) else 'false')
except:
  print('true')
" 2>/dev/null || echo "true"
}

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || echo "")
[ -z "$SESSION_ID" ] && exit 0

ENABLED=$(is_enabled)
[ "$ENABLED" = "false" ] && exit 0

LOG_FILE="/tmp/fence-prdgate-log-${SESSION_ID}.jsonl"

if [ "$MODE" = "mark-passed" ]; then
  SUBAGENT=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('tool_input',{}).get('subagent_type',''))
" 2>/dev/null || echo "")
  [ "$SUBAGENT" != "prd-gate" ] && exit 0

  # tool_response's exact shape for a Task-tool call isn't nailed down here —
  # try the plausible field names and fall back to scanning the whole payload.
  OUTPUT_TEXT=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
r=d.get('tool_response', d.get('tool_result',''))
if isinstance(r, dict):
  print(r.get('content', r.get('output', r.get('text', json.dumps(r)))))
else:
  print(r)
" 2>/dev/null || echo "")

  # The report template puts the header and verdict on separate lines
  # ("### GATE" then "READY" on the next line), not "GATE: READY" on one —
  # a pre-existing mismatch (this "GATE: READY" substring check predates
  # this telemetry addition) that meant gate_passed tracking below has
  # never actually fired against real prd-gate output. Fixed here rather
  # than left in place, since the new VERDICT parsing below would have
  # inherited the identical bug.
  VERDICT=$(echo "$OUTPUT_TEXT" | grep -A1 "^### GATE" | tail -1 | grep -oE "READY|BLOCKED|NEED_INFO" | head -1)

  if [ "$VERDICT" = "READY" ]; then
    echo "{\"event\":\"gate_passed\",\"ts\":$(date +%s)}" >> "$LOG_FILE"
  fi

  ATTEMPT=$(echo "$OUTPUT_TEXT" | grep -A1 "^### ATTEMPT" | tail -1 | grep -oE '[0-9]+' | head -1)
  [ -z "$ATTEMPT" ] && ATTEMPT="unknown"
  TASK_REF=$(echo "$OUTPUT_TEXT" | grep -m1 "^- Task reference:" | sed -E 's/^- Task reference: *//' | head -c 200)
  [ -z "$TASK_REF" ] && TASK_REF="unknown"
  if [ -n "$VERDICT" ]; then
    record_pipeline_metric "prd_gate_report" "$VERDICT" "$ATTEMPT" "$TASK_REF"
  fi

  exit 0
fi

# gate mode
[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

if grep -q '"event":"gate_passed"' "$LOG_FILE" 2>/dev/null; then
  exit 0
fi

if grep -q '"event":"nag_issued"' "$LOG_FILE" 2>/dev/null; then
  exit 0
fi

echo "{\"event\":\"nag_issued\",\"ts\":$(date +%s)}" >> "$LOG_FILE"

cat >&2 <<EOF

📋 PRD-GATE CHECK

This looks like the first product-code write this session. Before continuing,
use the Task tool with subagent_type "prd-gate" to check the plan for open
questions, edge cases, and the lens pass (Engineering/Security/Product/Legal,
plus UX/Data Science/Support where relevant) — same standard as this repo's
task-check, applied before code exists instead of after.

Supply: the checklist item reference (or a plain task description if none
applies), and attempt number (1 on first run).

If GATE = READY, proceed. If BLOCKED, resolve FIX_NOW issues yourself and
surface ASK_USER ones before writing code.

If this is genuinely trivial/ad hoc with no discrete checklist item, skip
this — same carve-out as task-check.

(This reminder fires once per session — it will not repeat.)
EOF

exit 2
