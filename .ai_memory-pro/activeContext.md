# Active Context Capsule
<!-- REQUIREMENT_BASELINE -->
- **Requirement Baseline**: 0 ([UNINITIALIZED])
- **State**: [IDLE]
- **Task ID**: none
- **Goal**: waiting for the first real task
- **Stage**: idle
- **Latest verified checkpoint**: none
- **Unverified work**: none
- **Next action**: follow the latest user request
- **Blockers**: none
- **Do not break**: none recorded
- **Task pack**: none
- **Resume Reads**: none
- **Archive pointer**: none
- **Updated**: __DATE__

## Capsule contract
- This is the only startup memory file. Keep it below 1,800 characters and 30 lines.
- If State is IDLE/PARKED or the task does not match the latest user request, do not open the old task pack.
- For a real continuation, read only the exact Task pack and Resume Reads listed above.
- Store raw wording, acceptance details, logs and handoff detail in the task pack or history, never here.
- After context compaction, reread only this capsule; never replay startup files or prior summaries.
