# Module Memory Overlays

> Purpose: path-scoped memory that is loaded only when touched files match `module-map.json`.

## How overlays work
- `module-map.json` maps `path_globs` to a `module_memory` file.
- Module memory is an overlay on top of global memory. It narrows context; it does not override user instructions or source code.
- If a task touches multiple modules, read only the matching overlays.
- If this README is too generic for a real project, create small files such as `modules/frontend.md`, `modules/backend.md`, or `modules/database.md`, then update `module-map.json`.

## Overlay template
```markdown
# Module: name

- **Scope**:
- **Owned paths**:
- **Key entry points**:
- **Important contracts**:
- **Common verification commands**:
- **Known pitfalls**:
- **Do not touch without confirmation**:
- **last_verified**:
- **status**: active
- **confidence**: medium
- **superseded_by**: none
```

## Rules
- Keep each module overlay under 120 lines.
- Prefer links to source files, tests, interfaces, and decisions instead of copying long content.
- Archive stale module notes through `history/index.jsonl`.
- Do not create a module overlay for a one-off task unless it will help future handoff.
