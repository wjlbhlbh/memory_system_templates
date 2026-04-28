# Memory Bootstrap For Cursor Rules

本项目启用 `.ai_memory` 记忆系统。进入任何工作前，Cursor Agent 必须：

1. 完整读取 `.ai_memory` 下所有 Markdown 文件
2. 先读 `projectbrief.md`，再读 `activeContext.md`
3. 再读取 `index.json` 并按顺序装载剩余文件
4. 发现未闭合 `[WIP]` / `[REWORK]` 时，先接管再工作
5. 改代码前重读目标文件最新快照
6. 无真实执行证据不得结案

如有冲突，以 `.ai_memory/projectbrief.md` 为准。
