# 进度与归档 (Progress)

## 使用规则
- 本文件由主 Agent (main agent) 单独写入；子 Agent 不直接编辑
- 只写已验证通过的事实
- 一条记录只写一个独立闭环
- 长任务必须拆成多个 checkpoint，小闭环通过后立即记录，不等大任务整体结束
- 结论必须能对应到真实证据，不写“应该没问题”
- 本文件是 rolling window / 近期窗口，不是永久流水账；只保留最近关键 checkpoint、当前仍影响判断的验证事实和 archive index / 归档索引
- 超过 120 行或最近记录超过 30 条时，把早期细碎记录移入 `history/`，本文件只保留当前关键 checkpoint 和归档链接
- 大段控制台输出、调研过程、完整交接和失败尝试不写入本文件；只写验证结论，详情放入 `history/` 或对应 `task-packs/*.md`

## 记录模板
- [YYYY-MM-DD] `[CHK-001]` `[TASK-001/无]` `[path/to/file]` 变更摘要。验证：PASS。verification evidence：`命令/测试/人工验证`。Requirement Checklist：`已覆盖/部分覆盖`。未执行：`如无写无`。剩余风险：`如无写无`

## Checkpoint 约定
- `CHK-xxx` 只给已验证通过的阶段成果编号
- 若是多 Agent 协作，只有主线完成合并并验证后，才写入 `progress.md`
- 若任务仍在继续，`activeContext.md` 记录进行中状态，`progress.md` 只保留已落地的真事实
- `[DONE]` 任务必须能回指 `masterTaskLedger.md` 或明确说明本任务无需账本
- 不能用“核心功能完成”替代 Requirement Checklist；未覆盖项必须写明

## 已完成记录
- 暂无

## 归档索引 (archive index)
- 暂无。归档后写入 `history/YYYY-MM-DD-progress-archive.md`，并在这里保留日期、范围、关联任务和一句话摘要。
