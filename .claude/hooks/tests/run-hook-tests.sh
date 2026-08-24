#!/usr/bin/env bash
# Runs every *.test.sh file in this directory and reports a combined
# pass/fail summary. Wired into CI as the `hooks-test` job
# (repo-template/.github/workflows/ci.yml) — every new or modified hook
# under .claude/hooks/tools/ gets a corresponding *.test.sh here before being
# considered done.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILED=0
for test_file in "${DIR}"/*.test.sh; do
  [ -e "$test_file" ] || continue
  echo "=== $(basename "$test_file") ==="
  if ! bash "$test_file"; then
    FAILED=1
  fi
  echo ""
done

if [ "$FAILED" -ne 0 ]; then
  echo "Hook tests FAILED"
  exit 1
fi

echo "All hook tests passed"
exit 0
