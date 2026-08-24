---
description: Run the full verification pipeline and record a pipeline-pass marker so a commit is unblocked.
argument-hint: [checklist item reference, or a plain task description]
---

Task reference: $ARGUMENTS

Run, in order, fixing and re-running on any failure before moving to the next step:

1. `npm run typecheck`
2. `npm run lint`
3. `npm run check:banned-folders` and `npm run check:payment-fields -- HEAD` — mechanized
   backstops for `rules.md` Rules 3 (banned folder names) and 4 (no payment-shaped
   fields); fix any violation before continuing rather than relying on the reviewer in
   step 5 to catch it.
4. `npm run test`
5. `npm run build`
6. Use the Task tool with subagent_type "automatic-code-reviewer" against every file changed this session (`git diff --name-only` against the base branch). Fix any violation reported.
7. Use the Task tool with subagent_type "task-check", supplying the task reference above, a work summary in your own words, and an attempt number. On FAIL, fix FIX_NOW issues and re-run task-check (max 3 attempts); surface ASK_USER issues to the user before proceeding. Do not treat this step as satisfied until task-check itself returns PASS.

Only once ALL of the above are clean:

8. Run `.claude/hooks/tools/complete-task-mark-passed.sh`.
9. Commit. Do not edit any file between step 8 and the commit — the marker is keyed to the exact working-tree state at step 8, and any further edit invalidates it, which will re-block the commit.

Do not skip steps, reorder them, or commit before step 7 has run against the exact tree being committed.
