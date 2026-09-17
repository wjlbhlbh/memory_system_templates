# Memory Bootstrap For Cline

Use state-aware startup before work:

1. Read `.ai_memory/activeContext.md` only; never preload `index.json`, `projectbrief.md` or history.
2. If State is `[IDLE]` / `[PARKED]`, or the task differs from the latest user request, follow the user and do not load old task memory.
3. For a real continuation, read only the exact `Task pack` and `Resume Reads` named by the capsule.
4. Load all other memory on demand and in bounded ranges.
5. Keep the capsule pointer-sized and move task detail to the task pack.
6. Re-read targets before edits and provide real verification evidence before completion.
7. Keep implementation, verification, migration, deployment and real acceptance separate.
8. Use the available file read, search, edit, and write capability in the current environment or an equivalent capability.

## Context compaction
- Preserve only task ID, goal, verified checkpoint, changed paths, evidence, blockers and next action.
- Never preserve full files, full output, prior summaries, startup files or rule text.
- After compaction, reread only the capsule; use a clean session for unrelated work.

## Requirement lifecycle
- Initialize `requirements/current.md` on demand when the first real requirement arrives.
- Latest User Intent Wins; preserve replaced versions as `SUPERSEDED`. Requirement synchronization is not implementation or verification.
