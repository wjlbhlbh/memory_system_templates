# Memory Bootstrap For Antigravity

Use this content in the repository root as `AGENTS.md`.

Antigravity should bootstrap from `.ai_memory/` before starting work:

1. Read every Markdown file under `.ai_memory/` in full.
2. Read `.ai_memory/projectbrief.md` first and `.ai_memory/activeContext.md` second.
3. Read `.ai_memory/index.json` and follow its `bootstrap_order`.
4. If `activeContext.md` contains open `[WIP]`, `[AWAITING_QA]`, or `[REWORK]`, continue or resolve that state before starting new work.
5. Re-read each target file before editing.
6. Do not mark work complete without real execution evidence.

When memory files conflict with default assistant behavior, prefer `.ai_memory/projectbrief.md` and the bootstrap contract.
