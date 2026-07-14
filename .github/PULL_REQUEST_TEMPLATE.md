## Summary

- 

## Type of change

- [ ] Template or memory-system rule
- [ ] Tool adapter
- [ ] Script or verification
- [ ] Documentation
- [ ] Example project
- [ ] Other

## Checklist

- [ ] I kept Fast startup lightweight and did not add unnecessary files to `startup_order`.
- [ ] `startup_order` still contains exactly `index.json`, `projectbrief.md`, and `activeContext.md`.
- [ ] Character, line, and single-line budgets still pass `memory-health.ps1`.
- [ ] Requirement lifecycle changes preserve Latest User Intent Wins, `SUPERSEDED` history, and separate implementation/verification states.
- [ ] Archive or migration changes preserve exact bytes and validate SHA-256 manifests.
- [ ] I avoided tool-specific file API names such as `view_file` or `read_file` in user-facing rules.
- [ ] I kept Agent-readable files as UTF-8 without BOM.
- [ ] I did not include secrets, private logs, production data, or local machine artifacts.
- [ ] I ran:

```powershell
powershell -ExecutionPolicy Bypass -File .\memory-health.ps1 -MemoryPath .\.ai_memory-pro
powershell -ExecutionPolicy Bypass -File .\tests\verify-memory-system.ps1
```

## Notes for maintainers

- 
