---
description: Autonomous end-to-end run for one checklist item — PRD-gate, TDD implementation, /complete-task, and an open PR. Designed to be handed to a forked agent and left unattended, one per item in a batch.
argument-hint: [checklist item, e.g. "1.4.5", or a plain task description]
---

Task: $ARGUMENTS

Run this checklist item end to end, stopping only for a genuine USER_REQUIRED
question. This is meant to run unattended — including as one of several
forked/worktree agents running concurrently on other items — so do not
narrate step-by-step to the user; report back only at a stopping point.

1. **PRD-gate.** Use the Task tool with subagent_type "prd-gate", supplying
   the task reference above and attempt=1. If BLOCKED, resolve FIX_NOW
   issues yourself; if any ASK_USER issue remains after that — this
   includes any Security or Legal/Compliance finding from the lens pass,
   which always needs a real answer, not an assumption — stop and ask. Do
   not proceed to implementation on a BLOCKED gate.
2. **Test-author.** Use the Task tool with subagent_type "test-author",
   supplying the task reference, the `prd-gate` report from step 1, and
   attempt=1. It writes the failing test(s) for this item and locks them —
   `test-lock.sh` will block any edit to those exact files from this point
   on. If BLOCKED, resolve FIX_NOW issues yourself and surface ASK_USER
   ones (a genuinely ambiguous/contradictory requirement) before
   proceeding. Do not skip this step and hand-write tests yourself — the
   separation is the point.
3. **Implement to GREEN, then refactor**, following this repo's `CLAUDE.md`
   exactly: strict types, 100% coverage, no banned folder names. Work
   against the tests `test-author` locked — do not edit them. If a locked
   test genuinely looks wrong, stop and tell the user exactly why rather
   than trying to edit around the lock; if `task-check` later finds a
   coverage gap `test-author` missed, add a **new** test file for it — a
   new file is never locked, only the ones `test-author` actually wrote.
4. **`/complete-task`**, supplying the same task reference. This runs the
   full verification pipeline and records the pipeline-pass marker — do not
   attempt to commit any other way.
5. **Open a PR** once committed, with a description that references the
   checklist item and links back to it. Apply the `agent-pr` label (create
   it on the repo first with `gh label create agent-pr --color ededed
   --description "opened by /run-task" 2>/dev/null || true` if it doesn't
   exist yet) so downstream automation can tell an agent-authored PR apart
   from a human's manual branch. Do not merge it.
6. **Report back**: the PR link, plus the full `prd-gate`, `test-author`,
   and `task-check` reports if any ever returned BLOCKED/FAIL along the
   way.

If `prd-gate`, `test-author`, or `task-check` hits its 3-attempt limit
without resolving, stop and report exactly what's unresolved — do not keep
retrying past the limit, and do not silently narrow scope to make the item
"pass."
