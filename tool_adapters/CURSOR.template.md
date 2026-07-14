# Memory Bootstrap For Cursor Rules

本项目启用 `.ai_memory` 记忆系统。进入任何工作前，Cursor Agent 必须执行 Fast startup：

1. 先读取 `.ai_memory/index.json`
2. 只读取 `startup_order` 中列出的启动文件
3. 发现真实未闭合 `[WIP]` / `[AWAITING_QA]` / `[REWORK]` 时，先接管再工作；若为 `[IDLE]` 或空模板，直接进入当前任务
4. 实施前必须先把用户原话 (raw wording) 翻译成：真实意图 (real intent)、成功标准、明确非目标、任务分级；若需求模糊，默认选最小且可回退的解释
5. 只要歧义会影响数据、公共行为、兼容性、权限边界或架构，必须先停在方案阶段确认
6. 其他记忆文件只在与当前任务、目标模块、接口、架构、历史决策、待办、踩坑或验证路径相关时按需读取
7. 完成启动后必须输出一行 Startup Summary：已读文件、当前状态、是否需要读取 `masterTaskLedger.md` 或 `task-packs/*.md`
8. 长任务、多 Agent、跨模块任务必须读取或创建 `masterTaskLedger.md` 任务；复杂任务必须读取或创建对应 `task-packs/*.md`，并遵守 required reading / do not read
9. 改代码前重读目标文件最新快照，并先识别本轮“禁止误伤项”
10. 使用当前环境可用的文件读取、搜索、编辑和写入等价能力 (current environment equivalent capability)；不要要求、假设或抱怨某个固定工具 API 名称
11. 读取或修改记忆文件必须使用 explicit UTF-8；若出现 mojibake/乱码，先修复可读性再继续业务改动
12. 连续开发、多 Agent 并行、准备中断或担心 context compression / 模型切换前，必须更新 `activeContext.md` 的恢复锚点，并让 `activeContext.md` 保持活跃窗口、`progress.md` 保持滚动窗口
13. 无真实执行证据和 Requirement Checklist 不得结案
14. 如果发生 context compression、模型切换或工具切换，先重跑 Fast startup，再从 `activeContext.md` 的最近 checkpoint 继续，而不是靠聊天记忆重建上下文

如有冲突，以 `.ai_memory/projectbrief.md` 为准。
## Requirement Lifecycle
- If `.ai_memory/requirements/current.md` is `[UNINITIALIZED]` and the user provides requirements or a PRD, initialize the baseline before implementation.
- Apply **Latest User Intent Wins**: a new explicit user requirement directly replaces the prior active version; record the old version as `SUPERSEDED`.
- Questions, hypotheticals, examples, quoted opinions, and unaccepted AI suggestions do not replace requirements.
- Update only affected memory files. Requirement synchronization does not mean implementation or verification is complete.
