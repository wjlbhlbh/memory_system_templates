# 连续开发与上下文恢复协议

这份协议回答 6 个实战问题：需求模糊时如何不误判、开发时如何不误伤其他模块、长任务如何持续写回、多个 LLM 如何接力、上下文压缩或切模型后如何恢复、记忆文档如何避免膨胀。

## 1. 需求先翻译，不按字面直接编码

成熟的记忆系统不会把“用户说的话”直接当作“实现方案”。
它会先把输入拆成 4 件事：

- 用户原话：保留原始表达，不篡改历史。
- 真实意图：用户真正想解决的问题，不等于他嘴里的技术术语。
- 成功标准：做到什么才算完成。
- 明确非目标：本轮不做什么，避免 AI 自己扩需求。

如果用户不懂编程，这一步更关键。默认策略不是“多问”，而是“先做最小、可回退、最不破坏现有行为的解释”。只有歧义会影响数据、兼容性、权限边界、公共行为或架构时，才停下来确认。

## 2. WIP 和记忆归档要分层

成熟系统不会把所有内容都堆进一个进度文件里，而是至少分成两层：

- `activeContext.md`：当前正在做什么。它保存 WIP、阶段、禁止误伤项、恢复锚点、多 Agent 分工。
- `progress.md`：已经验证通过了什么。这里只写 PASS 的事实，不写猜测和未验证工作。

这样做的好处是：

- 上下文压缩时，未完成状态不会丢。
- 已完成事实不会和临时猜测混在一起。
- 接管的人可以立刻分辨“什么是当前真相，什么是历史归档”。

## 3. 长任务必须 checkpoint 化

连续开发最怕“一大坨活做到最后才补记忆”。
正确做法是把长任务拆成多个 verified checkpoint：

- 每个 checkpoint 都有独立目标。
- 每个 checkpoint 都有真实验证。
- 通过后立刻写入 `progress.md`。
- 下一阶段开始前，把 `activeContext.md` 更新到最新状态。

建议在以下时机强制写回：

- 从 `[IDLE]` 进入真实任务时
- 方案锁定后
- 完成一个已验证子闭环后
- 启动或合并多 Agent 并行任务前后
- 准备结束当前轮次、担心上下文压缩、切换模型或工具前

## 4. 多 LLM 任务必须账本化

多个 LLM 交替开发时，不能靠聊天记录推断谁做过什么。复杂任务必须进入 `masterTaskLedger.md`：

- `[READY]`：可认领
- `[IN_PROGRESS]`：进行中，写明模型/工具、locked files、任务包
- `[BLOCKED]`：阻塞，写明恢复条件
- `[DONE]`：已完成，必须带 verification evidence 和交接要点

任务账本不是需求正文，也不是日志仓库。它只保留任务市场、依赖关系、锁定文件、验证证据和下一任务入口。大任务必须拆到“一次会话可闭环”的粒度，否则 LLM 会在理解、编码、验证、交接之间互相挤占上下文。

## 5. 单任务上下文包控制读取范围

如果一个任务需要很多背景，不要让模型到处翻文件，应该创建 `task-packs/*.md`。任务包必须写清：

- required reading：本任务必须读什么
- do not read：本任务不该读什么
- 要做什么、不要做什么
- acceptance：验收标准
- Requirement Checklist：需求覆盖表
- handoff：完成后的交接信息

任务包的价值不只是“告诉 AI 读什么”，更是“告诉 AI 不读什么”。这能显著减少上下文浪费，也能避免模型被无关历史带偏。

模块级记忆也遵守同一个原则。先用 `module-map.json` 根据本次触碰路径匹配模块，再只读取对应 `modules/*.md` overlay。模块 overlay 只记录该模块长期稳定的边界、接口、坑点和验证口径，不写全项目流水账，也不替代源代码、测试和主记忆文件。

## 6. 多 Agent 并行时必须有主线记录人

多子 Agent 并行不是问题，没人维护主线才是问题。

成熟做法是：

- 主 Agent (main agent) 维护 `activeContext.md`
- 主 Agent 也负责写 `progress.md`
- 主 Agent 负责更新 `masterTaskLedger.md`
- 子 Agent 只负责自己边界内的修改和验证
- 子 Agent 回传 4 类信息：目标边界、修改文件、验证结果、未解决风险
- 只有主 Agent 合并并复核后，才把结果写进 `progress.md`

否则最常见的问题就是：子任务做了很多，但上下文压缩一来，主线根本不知道哪些已经可信、哪些只是草稿。

## 7. 上下文压缩或切模型后的恢复顺序

成熟系统不会要求模型“记住整段对话”。
它要求模型“按文件化 checkpoint 恢复状态”。

恢复顺序应该固定为：

1. 只重新读取 `.ai_memory/activeContext.md`
2. 判断胶囊任务是否与用户最新要求一致；不一致则停止加载旧记忆
3. 确认是真实续接后，只读胶囊精确列出的 `Task pack` 与 `Resume Reads`
4. 只按需补读相关源码、接口、决策、测试文件
5. 从最近 verified checkpoint 继续

不应该做的事：

- 靠印象复述之前聊过什么
- 从头再读所有记忆文件
- 重放旧摘要、启动文件或完整工具输出
- 因为上下文丢了就重新走一遍前期分析

如果恢复需要旧日志、历史交接或过期任务细节，应先检索 `history/index.jsonl`，再打开命中的归档文件。可用根目录 `search-memory.ps1 -Query <text>` 或 `search-memory.ps1 -Tag <tag>` 缩小读取范围。

## 8. 完成前必须做需求覆盖复核

“测试通过”不等于“需求完成”。复杂功能结束前必须输出 Requirement Checklist：

| 需求/边界 | 状态 | verification evidence | 备注 |
|---|---|---|---|
| 用户明确要求的功能 | DONE / PARTIAL / BLOCKED | 测试命令、截图、日志或人工验证 | 未覆盖则写明原因 |

只要存在未实现、未验证或被 AI 擅自改写的需求，就不能标记 `[DONE]`。可用状态是 `[PARTIAL]`、`[AWAITING_QA]`、`[BLOCKED]` 或 `[REWORK]`。

## 9. 记忆文件的安全写法

记忆文件最怕的不是“没人写”，而是“谁都能写”。
因此应默认执行：

- `activeContext.md` 和 `progress.md` 是单写者文件，只允许主 Agent 写
- 子 Agent 只回传结果，不直接改主记忆
- 不限制具体工具、命令或编辑器；限制的是“依赖默认编码或隐式文本输出”的写法
- 记忆文件必须显式保持 UTF-8 无 BOM，写入后确认内容可读
- 长任务必须按 checkpoint 持续写回，不要最后一次性重写整份记忆
- 过期日志、长交接和旧任务细节移入 `history/`，避免启动文件持续膨胀
- `decisionLog.md`、`interfaces.md`、`pitfalls.md` 这类长期事实必须带 `status`、`last_verified`、`confidence`、`superseded_by` 字段，避免旧判断在后续项目阶段被当成新事实继续传播

## 10. 这套模板现在落地了什么

本仓库已经把以上协议前置到：

- `.ai_memory-pro/MEMORY.md`
- `.ai_memory-pro/index.json`
- `.ai_memory-pro/projectbrief.md`
- `.ai_memory-pro/agentRules.md`
- `.ai_memory-pro/activeContext.md`
- `.ai_memory-pro/masterTaskLedger.md`
- `.ai_memory-pro/module-map.json`
- `.ai_memory-pro/modules/README.md`
- `.ai_memory-pro/task-packs/README.md`
- `.ai_memory-pro/history/README.md`
- `.ai_memory-pro/history/index.jsonl`
- `.ai_memory-pro/progress.md`
- `search-memory.ps1`
- `tool_adapters/*.template.md`
- `tests/verify-memory-system.ps1`

也就是说，后续不是“靠操作者记得遵守”，而是“启动期模板和验证脚本共同约束”。
## 11. First real requirement completes business initialization

Creating `.ai_memory` is not enough. When a new project first receives a user requirement, PRD, requirement list, or prototype description, the main agent must initialize `requirements/current.md`, append the source event, update `projectbrief.md` and `activeContext.md`, and run `memory-health.ps1` before implementation. Large source documents stay outside the startup capsule and are referenced by path, summary, and SHA-256.

## 12. Latest user intent updates memory immediately

A new explicit user requirement directly replaces the prior active requirement. The old version is retained as `SUPERSEDED`; no second confirmation gate is required. The main agent calculates the affected memory routes and updates only those files. A synchronized requirement defaults to `implementation_pending` and `not_verified`, so a documentation update can never masquerade as completed code.

Use `record-requirement-change.ps1` for deterministic versioning and `requirements/change-log.jsonl` for audit. Questions, hypotheticals, examples, quotations, and AI proposals are not requirement events unless the user explicitly adopts them.
