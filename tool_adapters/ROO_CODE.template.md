# Memory Bootstrap For Roo Code

本项目的长期记忆入口不是单一 prompt，而是根目录 `.ai_memory/`。

强制规则：
1. 先读取 `.ai_memory/index.json`
2. 只读取 `startup_order` 中列出的启动文件
3. 非启动记忆文件只在与当前任务、目标模块、接口、架构、历史决策、待办、踩坑或验证路径相关时按需读取
4. 发现真实已有 `[WIP]` / `[AWAITING_QA]` / `[REWORK]` 时先接管，不得直接另开新任务；若为 `[IDLE]` 或空模板，直接进入当前任务
5. 任何编辑前必须重新读取目标文件
6. 没有真实运行证据，不得标记 `[DONE]`
