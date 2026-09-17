# Memory Hub

> Human and LLM navigation map. This file is on demand and is never startup payload.

## State-aware startup
1. Read `activeContext.md` only.
2. If it is IDLE/PARKED or does not match the latest user request, stop loading old task memory.
3. For a real continuation, read only its exact `task-packs/*.md` pointer and Resume Reads.
4. Never read `index.json`, `projectbrief.md`, progress, history, PRD assets or archives merely because a session started.

## Memory routes
- Durable project purpose and boundaries: `projectbrief.md`
- Effective requirements: `requirements/current.md`; audit: `requirements/change-log.jsonl`
- Architecture and stack: `architecture.md`, `systemPatterns.md`, `techContext.md`
- Contracts and decisions: `interfaces.md`, `decisionLog.md`, `pitfalls.md`
- Current task detail: the exact `task-packs/*.md` named by `activeContext.md`
- Verified recent facts: `progress.md`
- Older evidence: search `history/index.jsonl` before opening an archive
- Module overlays: consult `module-map.json` only after a touched path is known

## Context rules
- `index.json` is machine configuration for scripts, not an LLM startup document.
- Keep `activeContext.md` as a pointer-sized capsule; keep task packs bounded and task-specific.
- Do not copy full code, long command output, old summaries, credentials or production data into memory.
- On compaction preserve task ID, checkpoint, paths, evidence, blockers and next action only.
