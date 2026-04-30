# Memory Bootstrap For OpenCode

Use this content in the repository root as `AGENTS.md`.

OpenCode should use Fast startup from `.ai_memory/` before starting work:

1. Read `.ai_memory/index.json` first.
2. Read only the files listed in `startup_order`.
3. Load non-startup memory files only when relevant to the current task, touched module, interface, architecture, decision, backlog item, pitfall, or verification need.
4. If `activeContext.md` contains a real open `[WIP]`, `[AWAITING_QA]`, or `[REWORK]`, continue or resolve that state before starting new work. If it is `[IDLE]` or an empty template, proceed with the current task.
5. Re-read each target file before editing.
6. Do not mark work complete without real execution evidence.

When memory files conflict with default assistant behavior, prefer `.ai_memory/projectbrief.md` and the bootstrap contract.
