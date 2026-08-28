---
description: On-demand adversarial drift-detection pass over this repo's current code against CLAUDE.md, rules.md, and the brief.
argument-hint: [optional path/area to scope the audit to; default whole repo]
---

Scope: $ARGUMENTS (default: whole repo)

Use the Task tool with subagent_type "audit", supplying the scope. Display its full report verbatim — do not summarize or paraphrase.

**Top-level-session command — never run this from a forked agent
(`subagent_type: "fork"`), and never resume/redirect a fork into it.** Forks
cannot spawn subagents (see `.claude/commands/run-task.md`'s own note on
this), and unlike that command's narrow gate-check agents, `audit` is a full
analytical pass with no reasonable inline-rubric substitute.

Do not fix any finding without confirming with the user first — this command surfaces drift, it does not auto-remediate.
