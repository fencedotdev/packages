---
description: Autonomous run for one checklist item — PRD-gate, TDD implementation, /complete-task, and an open PR. Full end-to-end flow for ad hoc single-item use; implementation-only mode for plan-next.md's batch dispatch (PRD-gate/test-author already run for real by the top-level session). Designed to be handed to a forked agent and left unattended, one per item in a batch.
argument-hint: [checklist item, e.g. "1.4.5", or a plain task description]
---

Task: $ARGUMENTS

Run this checklist item end to end, stopping only for a genuine USER_REQUIRED
question. This is meant to run unattended — including as one of several
forked/worktree agents running concurrently on other items — so do not
narrate step-by-step to the user; report back only at a stopping point.

**If you are a forked agent (`subagent_type: "fork"`) running this command:
you cannot spawn subagents, full stop — not `prd-gate`, not `test-author`,
not anything else, no matter how the steps below are phrased.** This bit a
real project using this same pipeline three times across two sessions (a
fork calling the Agent/Task tool to spawn `prd-gate` mid-task — see
`fencedotdev/crossrepo-graph#79` for the full incident history) — evidently
a soft "don't do this" reminder alone isn't reliable once several tool calls
into a task, so the instruction below is not "try to remember not to" but a
concrete substitute: for each step that names a subagent, **read that
subagent's own definition file directly (`.claude/agents/prd-gate.md`,
`.claude/agents/test-author.md`, `.claude/agents/task-check.md`,
`.claude/agents/automatic-code-reviewer.md`) and perform its rubric
yourself, inline, in this same conversation** — same verdict categories
(READY/BLOCKED, PASS/FAIL, FIX_NOW/ASK_USER), same rigor, just without the
Agent/Task tool call. This is not a lesser substitute to reach for only
after a mistake; it is how a forked agent runs this command correctly the
first time. If you are *not* a forked agent (a top-level session, or another
agent type that genuinely can spawn subagents), spawning the real subagent
as written below is still preferred for the cleaner separation of concerns.

**Known, accepted limitation of this fallback:** several hooks only engage
on a genuine `PostToolUse` match against a real subagent call, and the
inline path above never produces one — so if you're a forked agent running
this command's full end-to-end flow (below) ad hoc, outside `plan-next.md`'s
batch dispatch, `test-lock.sh`'s structural lock won't technically engage
for you. **Behavioral substitute, since the technical one is absent in that
case: once you've written a test file under the inline `test-author` step,
treat it as locked by your own discipline for the rest of this task — do not
edit it to make a wrong implementation pass, and if it looks wrong, stop and
say why exactly as step 3 already instructs for a real lock.**
`prd-gate.sh`/`task-check.sh`'s telemetry writes to
`internal/audits/pipeline-metrics.jsonl` also go dark for fork-run items on
this path — an accepted, non-safety-critical gap, not something to work
around. **This ad hoc, single-item, all-in-one-fork flow is the fallback
path, not the primary one.** `plan-next.md`'s batch dispatch does not use
it: it runs real `prd-gate`/`test-author` from the top-level session first
(see `fencedotdev/crossrepo-graph#80`/`#81` for the origin of this
restructure — `test-lock.sh` itself had a real bug there too, not just a
fork-specific gap, independent of forking: its exact-path match compared a
relative locked path against an always-absolute real `file_path`, so the
lock silently never fired for anyone; fixed by normalizing both sides to a
repo-relative path before comparing — already applied to this file), then
hands each item to an **implementation-only** fork — see that mode below —
which gets a real, correctly-working lock. Use the full end-to-end flow
below only when running this command standalone, outside a `plan-next.md`
batch.

## Implementation-only mode

Used by `plan-next.md`'s phase 2 (see that file). You're a fork, given: the
task reference, a `prd-gate` report (already resolved, real, from the
top-level session), and a `test-author/<item>` branch to cherry-pick (real
locked test file(s) already committed there by the top-level session, from
a real `test-author` run). Do this instead of steps 1-2 below:

0. **Cherry-pick.** `git cherry-pick <test-author/<item> branch>` (or merge,
   if cherry-pick conflicts for a reason unrelated to the actual test
   content — investigate before falling back, don't reach for it as a
   first resort) into your own fresh worktree. Confirm the locked test
   file(s) are now present and match what the `prd-gate`/`test-author`
   reports you were handed describe. `test-lock.sh`'s lock is real and
   already active for these files (it was set when `test-author` ran, and
   correctly recognizes your worktree's own absolute path as the same
   repo-relative file) — you do not need step 2's inline-fallback
   self-discipline substitute here; the technical lock has you covered.

Then continue with steps 3-6 below exactly as written, using the supplied
`prd-gate` report wherever step 3/4 would otherwise reference step 1's
output. Do not re-run `prd-gate` or `test-author`, real or inline — both
already happened for real, before you were dispatched.

## Full end-to-end flow (ad hoc, single-item, outside a batch)

1. **PRD-gate.** Use the Task tool with subagent_type "prd-gate" (or, if
   you're a forked agent, apply `.claude/agents/prd-gate.md`'s rubric
   inline yourself — see above), supplying the task reference above and
   attempt=1. If BLOCKED, resolve FIX_NOW issues yourself; if any ASK_USER
   issue remains after that — this includes any Security or Legal/Compliance
   finding from the lens pass, which always needs a real answer, not an
   assumption — stop and ask. Do not proceed to implementation on a BLOCKED
   gate.
2. **Test-author.** Use the Task tool with subagent_type "test-author" (or,
   if you're a forked agent, apply `.claude/agents/test-author.md`'s rubric
   inline yourself — see above), supplying the task reference, the
   `prd-gate` report from step 1, and attempt=1. It writes the failing
   test(s) for this item and locks them — `test-lock.sh` will block any
   edit to those exact files from this point on. If BLOCKED, resolve
   FIX_NOW issues yourself and surface ASK_USER ones (a genuinely
   ambiguous/contradictory requirement) before proceeding. Do not skip this
   step and hand-write tests yourself without at least applying the same
   rubric — the separation of concerns is the point, even when it can't be
   a literal separate subagent call.
3. **Implement to GREEN, then refactor**, following this repo's `CLAUDE.md`
   exactly: strict types, 100% coverage, no banned folder names. Work
   against the tests `test-author` locked — do not edit them. If a locked
   test genuinely looks wrong, stop and tell the user exactly why rather
   than trying to edit around the lock; if `task-check` later finds a
   coverage gap `test-author` missed, add a **new** test file for it — a
   new file is never locked, only the ones `test-author` actually wrote.
4. **`/complete-task`**, supplying the same task reference. This runs the
   full verification pipeline and records the pipeline-pass marker — do not
   attempt to commit any other way. `/complete-task` itself spawns
   `automatic-code-reviewer`/`task-check` as subagents; if you're a forked
   agent, read `.claude/commands/complete-task.md` and apply those two
   agents' rubrics (`.claude/agents/automatic-code-reviewer.md`,
   `.claude/agents/task-check.md`) inline the same way, rather than letting
   `/complete-task` attempt a subagent spawn on your behalf.
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
