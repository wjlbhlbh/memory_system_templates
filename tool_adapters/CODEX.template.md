# Memory Bootstrap For Codex

Before work, use state-aware startup:

1. Read `.ai_memory/activeContext.md` only; do not preload `index.json`, `projectbrief.md`, progress or history.
2. If State is `[IDLE]` / `[PARKED]`, or the task does not match the latest user request, follow the latest request and stop loading old task memory.
3. For a real continuation, read only the exact `Task pack` and `Resume Reads` named by the capsule.
4. Load requirements, architecture, modules, decisions, pitfalls and history only when directly relevant.
5. Search large files first and read bounded ranges. Keep full files, long logs and command output out of memory.
6. Keep `activeContext.md` pointer-sized; put raw wording, acceptance details and handoff evidence in the task pack.
7. Re-read targets before edits and verify in proportion to risk. Distinguish implementation, verification, migration, deployment and real acceptance.
8. Latest explicit user intent wins; high-risk actions still follow platform and project authorization boundaries.
9. Use the available file read, search, edit, and write capability in the current environment or an equivalent capability.

## Context compaction
- Preserve only task ID, goal, verified checkpoint, changed paths, verification results, blockers and next action.
- Never preserve full files, full tool output, prior summaries, startup files or rule text.
- After compaction, reread only `activeContext.md`; open its exact task pack only when needed.
- Start a clean task between unrelated work instead of carrying stale context.

## Requirement lifecycle
- Initialize `requirements/current.md` on demand when the first real requirement arrives.
- Latest User Intent Wins; preserve replaced versions as `SUPERSEDED`. Requirement synchronization is not implementation or verification.

## Experience reuse (on demand)
- Before a relevant operation or the first retry, search `.ai_memory/pitfalls.md` and, when `AI_EXPERIENCE_DIR` is set, its `entries/EXP-*.md`; read only matching entries. Record verified, non-sensitive project lessons locally and cross-project lessons as separate shared files after checking for duplicates.
