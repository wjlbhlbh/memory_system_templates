# AI 快速执行规则 (Agent Rules)

## 1. 快速启动 (Fast startup)
- 新会话先读 `.ai_memory/index.json`，再读取 `startup_order` 中列出的启动文件。
- 非启动记忆文件只在与当前任务直接相关时读取，不做例行全量装载。
- `activeContext.md` 为 `[IDLE]` 或空模板时，直接进入当前任务。
- 发现真实未闭合任务、失败验证或人工 QA 状态时，先接管再继续。
- 完成启动后输出一行 Startup Summary：已读文件、当前状态、是否需要读取账本或任务包。

## 2. 意图澄清闸门 (Intent Gate)
- 开始实施前，先把用户原话 (raw wording) 翻译成：真实意图 (real intent)、成功标准、明确非目标、任务分级。
- 用户表达不专业或不精准时，不得按字面胡乱扩写需求；默认采用最小、可回退、最不破坏现有行为的解释。
- 只要歧义会改变数据、公共行为、兼容性、权限边界或架构，必须先停在方案阶段确认。

## 3. 默认执行策略
- L0 / L1 默认 direct execution：完成快速启动、完成意图翻译、读取相关代码后直接推进，不等待用户确认。
- L2 / L3 或不可逆、高风险、权限缺失、密钥缺失、外部平台操作，必须先停下确认。
- 小决策由 AI 基于仓库约定、现有代码和工程常识保守判断。

## 4. 开发纪律
- 先理解目标、影响范围和禁止误伤项，再修改。
- 修改前重读目标文件最新快照。
- 优先最小改动，复用现有模式，不随手引入新依赖、新抽象或大重构。
- 修改前先识别会被影响的模块、页面、接口、测试和流程；未验证前不得假设“其他地方不会受影响”。
- 遇到 bug、失败测试或异常行为时，先复现和定位根因，再修复。
- 复杂任务必须先拆成一次会话能闭环的最小任务；如果单次任务无法独立验证，先更新 `masterTaskLedger.md` 并建立 `task-packs/*.md`。
- 执行任务包时必须遵守其中的 required reading 和 do not read，避免重复读取无关历史。

## 5. 连续开发与记忆写回
- `activeContext.md` 是当前执行真相源，不只是备注页；在状态变化、计划锁定、阶段完成、并行分工、准备中断或担心上下文压缩时必须更新。
- `progress.md` 只记录已验证通过的 checkpoint；长任务拆成多个可验证小闭环，不等全部结束才补写。
- 多 Agent 并行时，`activeContext.md` 和 `progress.md` 只能由主 Agent (main agent) 写入；子 Agent 只回传目标边界、修改文件、验证结果和风险，不直接改主记忆。
- 多 Agent、长任务或跨模块任务的认领、阻塞、完成必须同步 `masterTaskLedger.md`；任务上下文过大时，用 `task-packs/` 承载自包含上下文包。
- 禁止用 shell 重定向、`Out-File`、`Set-Content`、`Add-Content` 或其他依赖默认编码的方式改记忆文件；只允许显式 UTF-8 写入或 patch-based 编辑。
- 长任务必须按 checkpoint 持续写回，不得等到任务结束时一次性重写整份记忆。

## 6. 恢复协议 (Resume Protocol)
- 发生 context compression、模型切换、工具切换或接管中断任务时，先重跑 Fast startup，再按 `activeContext.md` 的恢复锚点继续。
- 恢复时优先读取 `activeContext.md` 中列出的恢复必读文件，而不是重新回忆整段历史对话。
- 如果恢复锚点指向 `masterTaskLedger.md` 或 `task-packs/*.md`，只读取相关任务条目或任务包，不重新读取全量记忆。

## 7. 验证与完成
- 没有真实执行证据，不得标记完成。
- 完成前必须输出 Requirement Checklist：逐条列出用户要求、边界/非目标、实现状态、verification evidence、未覆盖项。
- 任一成功标准没有实现或没有验证证据时，不得标记 `[DONE]`，只能标记 `[PARTIAL]`、`[AWAITING_QA]`、`[BLOCKED]` 或 `[REWORK]`。
- L0 至少做静态检查或人工校验；L1 至少做相关测试、构建或可复现手工验证。
- 完成总结必须说明：改了什么、验证结果、未覆盖项、剩余风险。
- 验证后默认提交并推送源码；若无 Git、无 remote、无权限或网络失败，如实说明。

## 8. 按需记录 (demand-driven memory writes)
- `activeContext.md` 只在真实有价值的阶段更新，但一旦进入连续开发，就必须保持最新恢复锚点。
- `progress.md` 只记录已验证通过的独立闭环与 checkpoint。
- `masterTaskLedger.md` 记录任务市场、认领状态、locked files 和 verification evidence，不记录长日志。
- `task-packs/` 只放任务级 required reading、do not read、acceptance、Requirement Checklist 和 handoff，不放无关历史。
- `history/` 承接早期长日志和过期交接，避免 `activeContext.md` 与 `progress.md` 膨胀。
- `decisionLog.md`、`backlog.md`、`pitfalls.md`、`interfaces.md`、`architecture.md` 只在确有长期价值或相关改动时更新。
- 需要更完整的工程治理细则时，再读取 `engineeringRules.md`。
