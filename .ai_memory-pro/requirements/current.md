# 当前需求基线 (Current Requirements Baseline)

## 元数据
- **state**: [UNINITIALIZED]
- **baseline_version**: 0
- **updated_at**: __DATE__
- **latest_source**: none
- **source_sha256**: none
- **policy**: Latest User Intent Wins

## 使用规则
- 首次收到用户需求、PRD、需求清单或原型说明时，必须先完成本文件的业务初始化，再开始实施。
- 用户新的明确需求直接成为当前有效版本；相同 Requirement ID 的旧版本进入 `SUPERSEDED` 索引，无需二次确认。
- 问题、假设、示例、引用内容和未被用户采纳的 AI 技术建议不构成需求覆盖。
- 需求同步只表示记忆已更新，不表示代码已经实现或验证。
- 每次变更同时追加到 `change-log.jsonl`，不得改写或删除已有事件。

## 当前目标
- 尚未初始化。等待首份真实用户需求或 PRD。

## 当前有效需求

### REQ-001 示例结构（首次建档时替换本示例）
- **title**: 示例需求
- **version**: 0
- **statement**: 尚未初始化
- **source_ref**: none
- **implementation_status**: not_started
- **verification_status**: not_verified
- **affected_memory**: `projectbrief.md`, `activeContext.md`

## 当前业务规则
- 尚未初始化。

## 当前角色与权限
- 尚未初始化。

## 当前非目标
- 尚未初始化。

## 当前验收标准
- 尚未初始化。

## SUPERSEDED 需求索引
- 暂无。记录 Requirement ID、旧版本、新版本、变更事件和一句话原因；完整历史以 `change-log.jsonl` 为准。