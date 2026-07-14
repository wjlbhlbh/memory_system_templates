# Memory Hub

> Purpose: short human/LLM-readable index for Fast startup. Keep this file under 200 lines. Do not store long logs here.

## Current status
- **Project**: __PROJECT_NAME__
- **State**: [IDLE]
- **Latest verified checkpoint**: none
- **Active task**: none
- **Primary resume source**: `activeContext.md`

## Fast startup
1. Read `index.json`.
2. Read the remaining files in `startup_order`; `MEMORY.md` itself is on-demand and is not startup payload.
3. Use this file only when a human-readable navigation map is useful.
4. Load non-startup memory only when the current task, module, interface, decision, pitfall, backlog item, task pack, or verification path requires it.

## Resume Reads
- Default startup payload: `projectbrief.md`, `activeContext.md`. Load `agentRules.md` only when detailed governance is needed.
- If `activeContext.md` points to a ledger task, read the relevant entry in `masterTaskLedger.md`.
- If `activeContext.md` points to a task pack, read that exact `task-packs/*.md` file.
- If older context is needed, search `history/index.jsonl` first; do not browse all archives.

## Memory types
- **procedural**: rules for how agents should work. Start with `agentRules.md`; load `engineeringRules.md` only when governance detail is needed.
- **semantic**: durable project facts and contracts. Use `architecture.md`, `interfaces.md`, `systemPatterns.md`, `techContext.md`, `decisionLog.md`, and `pitfalls.md`.
- **episodic**: task history and verified events. Use `activeContext.md`, `progress.md`, `masterTaskLedger.md`, `task-packs/`, and `history/`.

## Module memory
- Read `module-map.json` to map touched paths to module overlays.
- Read `modules/README.md` before creating a module overlay.
- Module overlays are optional, small, and path-scoped. They do not replace source code or tests.

## Searchable history
- `history/index.jsonl` is the archive index.
- Use `search-memory.ps1 -Query <text>` or `search-memory.ps1 -Tag <tag>` before opening archive files.
- Archive files are not part of Fast startup unless listed in Resume Reads.

## Health rules
- Keep `activeContext.md` as the active window.
- Keep `progress.md` as the rolling window and archive index.
- Move old logs, long handoffs, and stale detail to `history/`.
- Do not store credentials, tokens, private keys, production data, or complete sensitive logs in memory files.
