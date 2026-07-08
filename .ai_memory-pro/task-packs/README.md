# 任务上下文包 (Task Packs)

> 用途：把复杂任务拆成 LLM 一次能吃完、能交付、能验证的独立上下文包。任务包不是知识库，不替代真实源码。

## 何时创建任务包
- 单次任务超过 3 个核心文件或跨前端/后端/数据库/外部平台。
- 需要多个 LLM 交替开发。
- 任务需要明确 required reading 和 do not read，避免上下文浪费。
- 用户反馈“AI 容易漏做细节”或任务必须逐条验收。

## 文件命名
- 推荐：`TASK-001-short-title.md`
- 与 `masterTaskLedger.md` 的任务 ID 保持一致。
- 每个任务包必须在 `masterTaskLedger.md` 中有对应任务条目；任务包和账本互为 backlink。

## 生命周期状态
- `[DRAFT]`：任务包草稿，尚未可认领。
- `[READY]`：边界、required reading、do not read 和 acceptance 已明确，可认领。
- `[IN_PROGRESS]`：已有主 Agent 或子 Agent 认领，必须同步 locked files。
- `[VERIFYING]`：实现已完成，正在跑验收或人工 QA。
- `[DONE]`：Requirement Checklist 已覆盖，verification evidence 已记录。
- `[ARCHIVED]`：任务包详情已折叠到 `history/`，账本保留索引。

## 任务包模板
```markdown
# Task Pack: TASK-001 任务标题

## status
- **state**: [DRAFT]
- **ledger backlink**: `masterTaskLedger.md#TASK-001`
- **owner**:
- **last_verified**:

## 0. required reading
1. 本文档
2. `path/to/interface-or-entry`
3. `path/to/reference-test`

## 1. do not read
- 不要全量读取 `.ai_memory/`
- 不要读取与本任务无关的历史归档
- 不要读取未列入 required reading 的大型目录，除非验证失败需要定位

## 2. 要做什么
- 明确写出本任务要交付的行为。

## 3. 不要做什么
- 明确写出本轮非目标、禁止误伤项和不允许顺手改的范围。

## 4. 执行步骤
1. 写或更新最小失败测试
2. 运行测试确认失败原因正确
3. 做最小实现
4. 运行验收命令
5. 更新交接记录

## 5. acceptance
- [ ] 成功标准 1
- [ ] 成功标准 2
- [ ] 相邻能力回归验证

## 6. Requirement Checklist
| 需求/边界 | 状态 | verification evidence | 备注 |
|---|---|---|---|
| 示例需求 | TODO |  |  |

## 7. handoff
- 修改文件:
- 验证命令:
- 未覆盖项:
- 剩余风险:
- 下个任务需要读取:
```

## 使用规则
- 一个任务包只服务一个可验证任务。
- 一个任务包必须有唯一状态，并与 `masterTaskLedger.md` 任务状态保持一致。
- 任务包创建、认领、验证、完成、归档时，都要同步账本 backlink。
- 任务包过长时，优先拆任务，而不是继续追加内容。
- 任务完成后，不把大段日志粘在任务包里；只保留关键 verification evidence，长日志归档到 `history/`。
