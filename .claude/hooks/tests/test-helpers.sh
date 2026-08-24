#!/usr/bin/env bash
# Shared assertion helpers for hook tests. Sourced (not executed) by each
# *.test.sh file — run-hook-tests.sh only globs and runs *.test.sh directly,
# so this file's own name deliberately doesn't match that pattern.

TESTS_RUN=0
TESTS_FAILED=0

assert_exit_code() {
  local expected="$1" actual="$2" desc="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$actual" != "$expected" ]; then
    echo "  FAIL: ${desc} (expected exit ${expected}, got ${actual})"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    echo "  ok: ${desc}"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  FAIL: ${desc} (expected output to contain: ${needle})"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    echo "  ok: ${desc}"
  fi
}

report_and_exit() {
  echo ""
  echo "$((TESTS_RUN - TESTS_FAILED))/${TESTS_RUN} passed"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
  fi
  exit 0
}
