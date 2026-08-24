---
description: Scan recently-merged PRs' review comments for recurring feedback and draft candidate rules.md additions to close the gap permanently. Run periodically, same cadence idea as /audit substituting for /plan-next occasionally — not part of the per-item /run-task loop.
argument-hint: [optional PR count to scan; default is everything since the last run]
---

Args: $ARGUMENTS

Use the Task tool with subagent_type "review-learnings", supplying the PR
count if given. Display its full report verbatim — do not summarize or
paraphrase.

For each `STRENGTHENS`-tagged draft, present it and ask whether to add it to
`.claude/automatic-code-review/rules.md`. For each `WEAKENS/LOOSENS`-tagged
draft, present it **individually, on its own**, and ask the same — never
batch these together with each other or with `STRENGTHENS` drafts, even if
the user seems inclined to approve everything at once.

Only write an approved draft into `rules.md` once the user has explicitly
confirmed it — append it after the existing repo-specific rules (Rule 6
onward, per `rules.md`'s own "a repo may append its own repo-specific
rules" convention), citing the PR(s) it was drawn from in the addition
itself. Do not write anything the user didn't explicitly confirm.
