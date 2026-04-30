# Memory Bootstrap For Cursor Rules

本项目启用 `.ai_memory` 记忆系统。进入任何工作前，Cursor Agent 必须执行 Fast startup：

1. 先读取 `.ai_memory/index.json`
2. 只读取 `startup_order` 中列出的启动文件
3. 其他记忆文件只在与当前任务、目标模块、接口、架构、历史决策、待办、踩坑或验证路径相关时按需读取
4. 发现真实未闭合 `[WIP]` / `[AWAITING_QA]` / `[REWORK]` 时，先接管再工作；若为 `[IDLE]` 或空模板，直接进入当前任务
5. 改代码前重读目标文件最新快照
6. 无真实执行证据不得结案

如有冲突，以 `.ai_memory/projectbrief.md` 为准。
