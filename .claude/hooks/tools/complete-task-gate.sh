#!/usr/bin/env bash
# Hard-blocks `git commit` unless a matching pipeline-pass marker exists for
# the CURRENT working tree. The marker is written only by
# complete-task-mark-passed.sh, itself only run as the last step of
# /complete-task once typecheck+lint+test+build+review+task-check are all
# clean. Keying on tree content (not session/time) means any edit made after
# the pipeline passed re-blocks the commit automatically — this does not try
# to detect whether /complete-task was literally invoked, only that the
# equivalent verification genuinely ran against the exact code being
# committed, which is the property that actually matters.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETTINGS_FILE="${PLUGIN_ROOT}/settings.json"

is_enabled() {
  python3 -c "
import json,sys
try:
  with open('${SETTINGS_FILE}') as f:
    d=json.load(f)
  print('true' if d.get('completeTaskGate',{}).get('enabled',True) else 'false')
except:
  print('true')
" 2>/dev/null || echo "true"
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('tool_input',{}).get('command',''))
" 2>/dev/null || echo "")

echo "$COMMAND" | grep -q "git commit" || exit 0

[ "$(is_enabled)" = "false" ] && exit 0

cd "$(git rev-parse --show-toplevel)" 2>/dev/null || exit 0
MARKER=".git/.fence-complete-task-passed"

if [ ! -f "$MARKER" ]; then
  echo "Blocked: no verified pipeline pass on record. Run /complete-task (typecheck+lint+test+build+code-review+task-check) before committing." >&2
  exit 1
fi

CURRENT_HASH=$( { git status --porcelain=v1 -uall; git diff HEAD; } | shasum -a 256 | cut -d' ' -f1)
RECORDED_HASH=$(cat "$MARKER")

if [ "$CURRENT_HASH" != "$RECORDED_HASH" ]; then
  echo "Blocked: working tree has changed since the last verified pipeline pass. Run /complete-task again before committing." >&2
  exit 1
fi

exit 0
