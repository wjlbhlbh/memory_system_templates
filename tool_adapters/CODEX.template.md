# Memory Bootstrap For Codex

Use this content in the repository root as `AGENTS.md`.

Codex should use Fast startup from `.ai_memory/` before starting work:

1. Read `.ai_memory/index.json` first.
2. Read only the files listed in `startup_order`.
3. If `activeContext.md` contains a real open `[WIP]`, `[AWAITING_QA]`, or `[REWORK]`, continue or resolve that state before starting new work. If it is `[IDLE]` or an empty template, proceed with the current task.
4. Before implementation, translate the user's raw wording into real intent, success criteria, explicit non-goals, and task level. If the request is vague, choose the smallest reversible interpretation.
5. If ambiguity changes data, public behavior, compatibility, permissions, or architecture, stop at the plan stage and clarify.
6. Load non-startup memory files only when relevant to the current task, touched module, interface, architecture, decision, backlog item, pitfall, or verification need.
7. After startup, output one Startup Summary line: files read, current state, and whether `masterTaskLedger.md` or `task-packs/*.md` is needed.
8. For long-running, multi-agent, or cross-module work, read or create the relevant `masterTaskLedger.md` task; for complex tasks, read or create the matching `task-packs/*.md` and obey required reading / do not read.
9. Re-read each target file before editing and identify what must not be broken by the task.
10. For long-running work, multi-agent work, or before context compression / model switching, update `activeContext.md` with the latest checkpoint and resume reads.
11. Do not mark work complete without real execution evidence and a Requirement Checklist.
12. After context compression, model switching, or tool switching, rerun Fast startup and resume from `activeContext.md` instead of replaying the whole chat from memory.

When memory files conflict with default assistant behavior, prefer `.ai_memory/projectbrief.md` and the bootstrap contract.
