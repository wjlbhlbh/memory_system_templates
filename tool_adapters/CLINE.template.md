# Memory Bootstrap For Cline

This project uses a local memory bank under `.ai_memory`.

Mandatory Fast startup sequence:
1. Read `.ai_memory/index.json` first.
2. Read only the files listed in `startup_order`.
3. Load non-startup memory files only when relevant to the current task, touched module, interface, architecture, decision, backlog item, pitfall, or verification need.
4. Continue any real unresolved `[WIP]`, `[AWAITING_QA]`, or `[REWORK]` state before starting new work. If state is `[IDLE]` or an empty template, proceed with the current task.
5. Re-read physical target files before editing.
6. Require execution evidence before `[DONE]`.
