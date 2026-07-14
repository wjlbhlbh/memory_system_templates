# Requirement-Driven Memory Lifecycle

This guide explains how AI Memory System Templates initializes project memory from the first real requirement and keeps memory synchronized when user intent changes.

## Core policy

**Latest User Intent Wins.** A new explicit user requirement immediately becomes the active requirement. The previous version remains auditable as `SUPERSEDED`; no second confirmation gate is required.

The following do not replace requirements unless the user explicitly adopts them:

- questions and requests for explanation;
- hypotheticals and examples;
- quoted third-party opinions;
- AI-generated technical suggestions;
- implementation guesses embedded in a PRD.

## First real requirement

Running `init-memory.ps1` creates the technical memory container. Business initialization happens when the first real requirement, PRD, requirement list, or prototype description arrives. The main agent must then:

1. preserve the source reference, summary, and SHA-256 when a source file exists;
2. initialize `.ai_memory/requirements/current.md`;
3. append requirement events to `.ai_memory/requirements/change-log.jsonl`;
4. update `projectbrief.md` and `activeContext.md`;
5. update only affected contracts, architecture, decisions, backlog, module memory, or task packs;
6. run `memory-health.ps1` before implementation.

Large PRDs are referenced, not copied into the startup capsule.

## Requirement and delivery states

Requirement synchronization and software delivery are separate:

- requirement baseline: current user intent;
- `implementation_pending`: code has not caught up;
- `implemented`: code changed but verification may remain;
- `not_verified`: no accepted execution evidence;
- `verified`: tests or human QA confirmed the behavior.

Updating memory must never convert implementation or verification to complete automatically.

## Deterministic requirement update

```powershell
.\record-requirement-change.ps1 `
  -MemoryPath .ai_memory `
  -RequirementId REQ-001 `
  -Title "Deletion policy" `
  -Statement "Users submit deletion requests for administrator review" `
  -SourceType user `
  -SourceRef "task-message-42"
```

Using the same Requirement ID creates a new monotonic version, replaces the active statement, records the prior version in the `SUPERSEDED` index, updates the active baseline version, and appends an audit event. Removal and later reactivation continue the same version sequence.

## Health and context budgets

```powershell
.\memory-health.ps1 -MemoryPath .ai_memory
```

The default startup capsule contains exactly:

1. `index.json`
2. `projectbrief.md`
3. `activeContext.md`

Health checks reject startup character overflow, oversized active or progress windows, excessive single-line content, broken JSONL, requirement baseline drift, and optional archive hash failures.

## Safe compaction

Prepare a reviewed compact replacement, inspect DryRun, and then apply:

```powershell
.\compact-memory.ps1 `
  -MemoryPath .ai_memory `
  -ActiveContextReplacementPath .\activeContext.compact.md

.\compact-memory.ps1 `
  -MemoryPath .ai_memory `
  -ActiveContextReplacementPath .\activeContext.compact.md `
  -Apply
```

Apply mode preserves the original bytes under `.ai_memory_archive/`, creates a manifest with SHA-256, updates the history index, and marks archive files read-only.

## Legacy migration

```powershell
.\migrate-memory.ps1 -TargetPath .
.\migrate-memory.ps1 -TargetPath . -Apply
```

Migration defaults to DryRun. Apply mode creates an immutable pre-migration backup, upgrades the three-file startup and budgets, adds missing requirement lifecycle files, and remains idempotent. It does not silently compact project-specific active history.

## Verification for contributors

```powershell
powershell -ExecutionPolicy Bypass -File .\memory-health.ps1 -MemoryPath .\.ai_memory-pro
powershell -ExecutionPolicy Bypass -File .\tests\verify-memory-system.ps1
```
