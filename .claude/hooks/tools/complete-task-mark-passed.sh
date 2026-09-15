#!/usr/bin/env bash
# Records that the full verification pipeline (typecheck+lint+test+build+
# automatic-code-reviewer+task-check) has passed against the CURRENT working
# tree. Run only as the last step of /complete-task, once everything is
# clean. Keyed on tree content, not session ID, so any further edit made
# after this point invalidates the marker again automatically.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# git rev-parse --git-dir (not a hardcoded ".git/") — in a linked worktree
# (git worktree add), ".git" at the worktree root is a FILE (a gitdir:
# pointer), not a directory, so writing into ".git/<name>" fails outright
# there. --git-dir resolves to the real per-worktree git directory in both
# cases (plain ".git" for a normal checkout, ".git/worktrees/<name>" for a
# linked worktree) and is itself worktree-private, which is the right scope
# for a marker keyed to one worktree's own working-tree content.
GIT_DIR="$(git rev-parse --git-dir)"
HASH=$( { git status --porcelain=v1 -uall; git diff HEAD; } | shasum -a 256 | cut -d' ' -f1)
echo "$HASH" > "${GIT_DIR}/.fence-complete-task-passed"
echo "Recorded pipeline pass for tree hash ${HASH:0:12}"
