# 记忆归档 (History Archive)

> 用途：控制长期项目中的文档膨胀。当前状态留在 `activeContext.md`，已验证事实留在 `progress.md`，过期细节进入本目录。

## archive 规则
- `activeContext.md` 只保留当前任务、恢复锚点、Resume Reads 和最近未闭合状态。
- `progress.md` 只保留近期 checkpoint 和仍会影响当前判断的验证事实。
- `masterTaskLedger.md` 只保留任务索引和关键状态，不粘贴长日志。
- 早期长日志、过期交接、已完成任务细节、调研长文移入本目录。
- 使用 rolling window / 近期窗口策略：主记忆文件负责接手，`history/` 负责追溯；不要让旧细节重新进入 Fast startup。
- 每次归档后，必须在来源文件留下 archive index / 归档索引链接，说明日期、范围、关联任务和一句话摘要。
- 如果归档内容恢复时必读，必须同时写入 `activeContext.md` 的 Resume Reads；否则默认不读归档。

## 建议命名
- `YYYY-MM-DD-progress-archive.md`
- `YYYY-MM-DD-task-TASK-001-handoff.md`
- `YYYY-MM-DD-research-topic.md`

## 归档摘要模板
```markdown
# Archive: 标题

- **日期**:
- **来源文件**:
- **归档原因**:
- **保留摘要**:
- **关联任务**:
- **verification evidence**:
- **恢复时是否必读**: 否。若为是，必须同时写入 `activeContext.md` 的 Resume Reads。
```

## 禁止事项
- 不要把当前未完成任务直接移入归档。
- 不要让归档文件进入 Fast startup。
- 不要在归档里保存密钥、令牌、生产数据或完整敏感日志。
