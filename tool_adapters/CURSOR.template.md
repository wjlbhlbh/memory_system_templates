# Cursor 状态感知记忆入口

开始工作前：

1. 只读取 `.ai_memory/activeContext.md`；不得预读 `index.json`、`projectbrief.md`、进度或历史。
2. 状态为 `[IDLE]` / `[PARKED]`，或旧任务不匹配用户最新要求时，直接执行最新要求，不加载旧任务包。
3. 只有真实续接时，才读取胶囊指定的精确 `Task pack` 与 `Resume Reads`。
4. 其他记忆全部按任务需要、按最小范围加载；大文件先搜索再分段读取。
5. 胶囊只保存任务 ID、状态、目标、checkpoint、下一步和指针，详细内容放任务包。
6. 修改前重读目标文件；完成前提供真实验证证据，并区分实现、验证、迁移、部署和真实验收。
7. Use the available file read, search, edit, and write capability in the current environment or an equivalent capability.

## 上下文压缩
- 只保留任务 ID、目标、最近验证点、变更路径、验证结果、阻塞项和下一步。
- 禁止保留完整文件、完整输出、旧摘要、启动文件或规则正文。
- 压缩后只重读胶囊；不相关的新任务使用干净会话。

## 需求生命周期
- 首份真实需求到达时按需初始化 `requirements/current.md`。
- Latest User Intent Wins；旧版本记为 `SUPERSEDED`，需求同步不等于实现或验证。

## 经验复用（按需）
- 相关操作前或首次失败准备重试时，搜索 `.ai_memory/pitfalls.md`；若设置了 `AI_EXPERIENCE_DIR`，也搜索其中 `entries/EXP-*.md`，只读命中条目。经验证且无敏感信息的项目经验写本项目，通用经验查重后新增独立共享文件。
