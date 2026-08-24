#!/usr/bin/env bash
# Blocks git commands that bypass safety checks or are destructive, and
# blocks modifications to quality-gate/pipeline-control config files —
# whether attempted via Bash or directly via Edit/Write/MultiEdit.
# Triggered by PreToolUse on both Bash and Edit|Write|MultiEdit tool calls;
# branches on tool_name since the two need genuinely different checks.
#
# The Edit/Write/MultiEdit branch and the PROTECTED_FILES additions below
# (package.json, package-lock.json, .claude/) were added alongside the
# continue-task-sweep.yml automation — this hook's own protected-file check
# previously only ran on the Bash tool, so a direct Edit/Write call to
# .github/workflows/ or .eslintrc bypassed it entirely. That gap mattered
# little while only interactive/human-watched sessions could trigger it; it
# matters a great deal more once an unattended, comment-fed sweep can push
# code on its own.
#
# The Edit/Write/MultiEdit branch only enforces when FENCE_CONTINUE_TASK_SWEEP
# is set — deliberately, not an oversight. Wiring it unconditionally would
# block every normal interactive/founder-approved session from ever editing
# .claude/, package.json, or .github/workflows/ via Edit/Write at all, which
# is real, legitimate, routine pipeline-development work (this exact repo's
# own history is full of it). The env var is set only in
# continue-task-sweep.yml's claude-code-action step, so this branch is a
# no-op everywhere except that one unattended context — the only place this
# protection was ever meant to apply. The Bash branch above is unaffected
# and stays always-on, unchanged from before.

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")

PROTECTED_FILES=(
  ".eslintrc"
  "eslint.config"
  "vitest.config"
  ".github/workflows"
  "package.json"
  "package-lock.json"
  ".claude/"
)

if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('tool_input',{}).get('command',''))
" 2>/dev/null || echo "")

  BLOCKED_PATTERNS=(
    "--no-verify"
    "--force-with-lease"
    "push --force"
    "push -f "
    "reset --hard"
    "checkout -- "
    "restore \."
    "clean -f"
    "branch -D"
  )

  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    # -- terminates option parsing before $pattern: BSD grep (macOS's default)
    # otherwise treats a pattern starting with "--" (e.g. --no-verify) as an
    # unrecognized flag, errors out, and the match silently never fires.
    if echo "$COMMAND" | grep -q -- "$pattern"; then
      echo "Blocked: This command bypasses safety checks (matched: ${pattern})" >&2
      exit 1
    fi
  done

  for protected in "${PROTECTED_FILES[@]}"; do
    if echo "$COMMAND" | grep -q -- "$protected"; then
      echo "Blocked: Modifications to quality-gate configuration files require explicit approval." >&2
      exit 1
    fi
  done

  exit 0
fi

if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
  [ "${FENCE_CONTINUE_TASK_SWEEP:-}" != "true" ] && exit 0

  FILE_PATH=$(echo "$INPUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
inp=d.get('tool_input',{})
print(inp.get('file_path', inp.get('path', '')))
" 2>/dev/null || echo "")
  [ -z "$FILE_PATH" ] && exit 0

  for protected in "${PROTECTED_FILES[@]}"; do
    if echo "$FILE_PATH" | grep -q -- "$protected"; then
      echo "Blocked: ${FILE_PATH} is a quality-gate/pipeline-control configuration file — modifications require explicit approval, not an unattended write." >&2
      exit 1
    fi
  done

  exit 0
fi

exit 0
