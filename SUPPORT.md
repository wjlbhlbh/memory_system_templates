# Support

## Where to ask

- **Bug reports:** use the Bug report issue form.
- **Feature ideas:** use the Feature request issue form.
- **Tool adapter requests:** use the Tool adapter request form.
- **Open-ended questions, showcases, and usage stories:** use GitHub Discussions.

## Before opening an issue

1. Search existing issues and discussions.
2. Run the verification script:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\verify-memory-system.ps1
```

3. Remove secrets, private logs, production data, and oversized memory files from examples.

## What helps most

- The AI coding tool you use: Codex, Claude Code, Cursor, Cline, OpenCode, Roo Code, Antigravity, or another tool.
- Your OS and shell.
- The command you ran.
- The smallest project shape that reproduces the issue.
- Whether the issue is about startup memory, active context, progress history, module memory, task packs, adapters, or encoding.
