# AI 快速执行规则 (Agent Rules)

## 1. 状态感知启动 (State-aware startup)
- 新会话只读 `.ai_memory/activeContext.md`；`index.json`、`projectbrief.md` 和其他记忆文件都不是启动载荷。
- `activeContext.md` 为 `[IDLE]` / `[PARKED]`，或旧任务与用户最新要求不匹配时，直接执行最新要求，不打开旧任务包。
- 只有用户确实在续接当前任务时，才读取胶囊中精确列出的 `Task pack` 与 `Resume Reads`。
- 需求、架构、模块、决策、踩坑、进度和历史只在当前任务需要时按需读取；历史先查索引再打开正文。
- 大文件先搜索定位再分段读取，禁止把完整文件、长日志或完整命令输出塞进启动上下文。

## 2. 意图澄清闸门 (Intent Gate)
- 开始实施前，先把用户原话 (raw wording) 翻译成：真实意图 (real intent)、成功标准、明确非目标、任务分级。
- 用户表达不专业或不精准时，不得按字面胡乱扩写需求；默认采用最小、可回退、最不破坏现有行为的解释。
- 只要歧义会改变数据、公共行为、兼容性、权限边界或架构，必须先停在方案阶段确认。

## 3. 默认执行策略
- L0 / L1 默认 direct execution：完成快速启动、完成意图翻译、读取相关代码后直接推进，不等待用户确认。
- L2 / L3 或不可逆、高风险、权限缺失、密钥缺失、外部平台操作，必须先停下确认。
- 小决策由 AI 基于仓库约定、现有代码和工程常识保守判断。

## 4. 工具能力适配
- 使用当前环境可用的文件读取、搜索、编辑和写入等价能力 (available file read/search/edit/write capability in the current environment)；不要要求、假设或抱怨某个固定工具 API 名称。
- 如果某项能力在当前环境没有同名工具，先寻找等价能力、命令行、MCP、IDE 能力或补丁编辑能力；只有确实无法完成任务时才说明阻塞。
- 规则只约束行为结果，不绑定具体工具实现；不同 AI 编程工具可以用自己的文件查看、搜索、编辑、测试和浏览能力完成同一协议。

## 5. 开发纪律
- 先理解目标、影响范围和禁止误伤项，再修改。
- 修改前重读目标文件最新快照。
- 优先最小改动，复用现有模式，不随手引入新依赖、新抽象或大重构。
- 修改前先识别会被影响的模块、页面、接口、测试和流程；未验证前不得假设“其他地方不会受影响”。
- 遇到 bug、失败测试或异常行为时，先复现和定位根因，再修复。
- 复杂任务必须先拆成一次会话能闭环的最小任务；如果单次任务无法独立验证，先更新 `masterTaskLedger.md` 并建立 `task-packs/*.md`。
- 执行任务包时必须遵守其中的 required reading 和 do not read，避免重复读取无关历史。

## 6. 连续开发与记忆写回
- `activeContext.md` 是指针型启动胶囊；只保存任务 ID、状态、目标、最近验证 checkpoint、下一步和精确恢复指针，详细内容进入任务包或历史。
- `progress.md` 只记录已验证通过的 checkpoint；长任务拆成多个可验证小闭环，不等全部结束才补写。
- 多 Agent 并行时，`activeContext.md` 和 `progress.md` 只能由主 Agent (main agent) 写入；子 Agent 只回传目标边界、修改文件、验证结果和风险，不直接改主记忆。
- 多 Agent、长任务或跨模块任务的认领、阻塞、完成必须同步 `masterTaskLedger.md`；任务上下文过大时，用 `task-packs/` 承载自包含上下文包。
- 读取或修改记忆文件必须使用 explicit UTF-8；任何工具、命令、编辑器或补丁方式都可以使用，但不得依赖默认编码或隐式文本输出 (default encoding / implicit text output)，写入后必须保持可读的 UTF-8 文本。
- 如果记忆文件出现 mojibake/乱码，先停止业务改动，使用 explicit UTF-8 重新读取或修复到可读文本，再继续执行任务。
- 长任务必须按 checkpoint 持续写回，不得等到任务结束时一次性重写整份记忆。
- `activeContext.md` 必须保持 bounded startup capsule / 有界启动胶囊：不得保存用户原话全文、完整文件、长推理、旧摘要、旧交接或细碎日志；这些内容移入 `task-packs/` 或 `history/`。
- `progress.md` 必须保持 rolling window / 滚动窗口：只保留近期关键 checkpoint、当前仍会影响判断的验证事实和 archive index / 归档索引链接。

## 7. 恢复协议 (Resume Protocol)
- 发生 context compression、模型切换、工具切换或接管中断任务时，只重读 `activeContext.md`。
- 确认是同一任务后，再读取胶囊精确列出的任务包和 Resume Reads；不得重放启动文件、旧摘要或整段历史对话。
- 不相关的新任务应使用干净会话，不续接陈旧上下文。

## 8. 验证与完成
- 没有真实执行证据，不得标记完成。
- 完成前必须输出 Requirement Checklist：逐条列出用户要求、边界/非目标、实现状态、verification evidence、未覆盖项。
- 任一成功标准没有实现或没有验证证据时，不得标记 `[DONE]`，只能标记 `[PARTIAL]`、`[AWAITING_QA]`、`[BLOCKED]` 或 `[REWORK]`。
- L0 至少做静态检查或人工校验；L1 至少做相关测试、构建或可复现手工验证。
- 完成总结必须说明：改了什么、验证结果、未覆盖项、剩余风险。
- 验证后默认提交并推送源码；若无 Git、无 remote、无权限或网络失败，如实说明。

## 9. 按需记录 (demand-driven memory writes)
- `activeContext.md` 只在真实有价值的阶段更新，但一旦进入连续开发，就必须保持最新恢复锚点。
- `progress.md` 只记录已验证通过的独立闭环与 checkpoint。
- `masterTaskLedger.md` 记录任务市场、认领状态、locked files 和 verification evidence，不记录长日志。
- `task-packs/` 只放任务级 required reading、do not read、acceptance、Requirement Checklist 和 handoff，不放无关历史。
- `history/` 承接早期长日志和过期交接，避免 `activeContext.md` 与 `progress.md` 膨胀。
- `decisionLog.md`、`backlog.md`、`pitfalls.md`、`interfaces.md`、`architecture.md` 只在确有长期价值或相关改动时更新。
- 需要更完整的工程治理细则时，再读取 `engineeringRules.md`。
## 10. Requirement lifecycle
- If `requirements/current.md` is `[UNINITIALIZED]` and the user supplies requirements, a PRD, a requirement list, or a prototype description, initialize the requirement baseline before implementation.
- Apply **Latest User Intent Wins**: every new explicit user requirement directly replaces the prior active version without another confirmation gate.
- Preserve the prior version as `SUPERSEDED` in `requirements/change-log.jsonl`; never silently delete requirement history.
- Questions, hypotheticals, examples, quoted opinions, and unaccepted AI suggestions do not replace requirements.
- Update only affected memory: project scope -> `projectbrief.md`; current execution -> `activeContext.md`; contracts or permissions -> `interfaces.md`; architecture -> `architecture.md`; long-term trade-offs -> `decisionLog.md`; cancellation or delay -> `backlog.md` and the task ledger.
- Requirement synchronization does not mean implementation or verification is complete. New or changed requirements default to `implementation_pending` and `not_verified`.

## 11. 前端 UI 防堆砌铁律 (UI Anti-Pile-Up Hard Rules)
- 涉及任何前端界面 (Web / 移动端 / 管理后台 / 用户前台 / 小程序等) 时，除通用开发纪律外，还必须遵守以下铁律；完整方法论见 `engineeringRules.md` 第 12 节。
1. 动手前先定“这屏给谁、完成哪一件事”，再决定放什么；能收进二级/标签页/抽屉的绝不平铺。
2. 新功能先判断是否与现有模块同类；同类则并入，不新开整块。顶层导航 ≤ 5–7 项。
3. 新增 UI 前过“自检 5 问”：给谁用 / Top3 任务 / 必看置顶 / 偶用收起 / 可省即删；答不出先别做。
4. 文字克制：短标签、删简介段、按钮写动作词、数字 > 长句；不用变量名/报错码/TODO 等开发术语当界面文字。
5. 颜色用令牌、语义优先、预留暗色；沿用项目既有品牌色不改色调，改色须先确认；同语义状态全站同色同话，不擅自换色。
6. 必须设计四态：有数据 / 空态 / 加载中 / 出错。先定响应式断点，窄屏不破版。
7. a11y：对比度 WCAG AA，键盘可操作，focus 可见。
8. 导航名 = 页面标题 = 按钮文案。
9. 覆盖多角色权限差异；功能可隐藏可下架。
10. 先出原型给人看再写码；交付不破坏现有功能、状态文案全站统一。
11. 同屏 > 4–5 个平级块 → 二级导航互斥切换（任意时刻只展示一个模块，不靠滚动定位）。
12. 长列表行信息密 → 行点抽屉看详情，行内只留主值；偶用区块收抽屉 / 折叠；概览 / KPI 上提首屏。
13. 单块长列表 → 分页 / 懒加载 + 内部滚动封顶（容器高度用令牌约束，不撑高整页）。
14. 纯 UI 重构只加纯 UI 状态变量，不动业务逻辑 / 接口 / 权限 / 路由 / 文案，不引入新依赖。
