# Memory Bootstrap For Cline

This project uses a local memory bank under `.ai_memory`.

Mandatory startup sequence:
1. Read every Markdown file under `.ai_memory`.
2. Read `projectbrief.md` first and `activeContext.md` second.
3. Read `index.json` and follow its `bootstrap_order`.
4. Continue any unresolved `[WIP]` or `[REWORK]` state before starting new work.
5. Re-read physical target files before editing.
6. Require execution evidence before `[DONE]`.
