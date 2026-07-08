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
- [ ] I avoided tool-specific file API names such as `view_file` or `read_file` in user-facing rules.
- [ ] I kept Agent-readable files as UTF-8 without BOM.
- [ ] I did not include secrets, private logs, production data, or local machine artifacts.
- [ ] I ran:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\verify-memory-system.ps1
```

## Notes for maintainers

- 
