# 需求驱动的记忆生命周期优化设计

> **历史 V2 设计：** V3 已将三文件启动替换为仅加载 `activeContext.md` 的状态感知启动。下文保留为设计历史，不是当前运行规则。

- **日期**：2026-07-14
- **状态**：已获用户方向确认
- **适用仓库**：AI Memory System Templates
- **核心策略**：Latest User Intent Wins（最新明确用户需求直接覆盖旧需求基线）

## 1. 背景

现有模板已经具备 Fast startup、活跃窗口、滚动进度、任务包、模块记忆和历史索引，但仍存在四类问题：

1. 启动预算主要按行数验证，无法阻止单行超长内容导致上下文爆满。
2. 默认启动文件较多，`bootstrap_order` 仍可能被误解为全量启动顺序。
3. 新项目首次收到用户需求或 PRD 后，没有强制完成“业务记忆初始化”。
4. 用户后续修改需求时，没有统一的需求版本、覆盖、影响传播和审计协议。

本设计将记忆系统从静态模板升级为由需求事件驱动的生命周期系统。

## 2. 已确认用户意图

### 2.1 首次建档

新项目创建 `.ai_memory` 只代表技术模板已安装。首次收到真实用户需求、PRD、需求清单、原型说明或其他项目资料后，系统必须完成第一次业务建档：

- 保存来源与用户原始表达。
- 形成当前需求基线。
- 填充项目目标、范围、非目标、业务规则和待办。
- 更新当前任务和恢复锚点。
- 按影响更新相关长期记忆。
- 验证启动预算、引用和状态一致性。

### 2.2 需求变更

当用户提出新的明确需求、修改、取消或替换说明时：

- 新表达立即成为当前有效需求。
- 不要求用户再次确认。
- 旧需求不得继续以 active 状态存在。
- 旧版本保留为审计历史，标记为 `SUPERSEDED`。
- 自动计算并更新受影响的记忆文件。
- “需求已更新”和“代码已实现/已验证”必须保持不同状态。

### 2.3 不构成需求覆盖的内容

以下内容不能自动覆盖需求基线：

- 用户提出的问题而非要求。
- 假设、举例、头脑风暴和未选定方案。
- 用户引用的第三方观点但未表示采纳。
- AI 自己提出的技术建议。
- PRD 中的技术实现猜测，除非用户明确要求作为约束。

## 3. 方案比较

### 方案 A：所有内容直接写入现有 Markdown

优点：实现最简单。

缺点：无法可靠区分新旧需求，容易重复、冲突和无限膨胀；不采用。

### 方案 B：需求事件日志作为唯一真相，动态生成全部 Markdown

优点：结构化程度最高，审计能力强。

缺点：引入生成器、双向同步和格式迁移，超出当前模板所需复杂度；暂不采用。

### 方案 C：当前需求基线 + 追加式变更日志 + 选择性传播（采用）

- `requirements/current.md` 保存当前有效需求基线。
- `requirements/change-log.jsonl` 保存追加式需求事件和版本关系。
- 原始大文档不复制进启动胶囊，只保存来源路径、摘要和哈希。
- 需求变化后按路由更新 projectbrief、activeContext、interfaces、architecture、decisionLog、backlog、task pack 等相关文件。
- 旧版本进入变更日志或不可变归档，不在当前基线中继续生效。

该方案在可追溯性、复杂度和上下文成本之间最平衡。

## 4. 目标分层

### L0：启动胶囊

默认只加载：

1. `index.json`
2. `projectbrief.md`
3. `activeContext.md`

启动胶囊负责当前项目边界、当前任务、最新需求版本、最近验证、下一步和风险，不承载完整需求历史。

### L1：当前有效知识

按需读取：

- `requirements/current.md`
- `progress.md`
- `agentRules.md`
- `architecture.md`
- `interfaces.md`
- `decisionLog.md`
- `pitfalls.md`
- `backlog.md`
- 模块记忆和任务包

### L2：不可变历史

- `.ai_memory/history/index.jsonl` 保留小型索引。
- `.ai_memory_archive/` 保存归档载荷、manifest 和 SHA-256。
- 初次迁移可保存完整原文件快照；日常滚动只归档被移出的段落或被取代版本。

## 5. 需求数据模型

### 5.1 当前需求基线

`requirements/current.md` 至少包含：

- baseline version
- updated_at
- source references
- 项目目标
- 当前有效功能需求
- 当前有效业务规则
- 当前有效角色和权限
- 当前有效非目标
- 当前有效验收标准
- 已取消或被取代需求的索引
- 尚未实现和尚未验证的状态

每条需求使用稳定 ID，例如 `REQ-001`。需求 ID 不因措辞变化而变化；业务含义发生替换时版本递增。

### 5.2 需求变更日志

`requirements/change-log.jsonl` 每行一个事件，至少包含：

- `event_id`
- `requirement_id`
- `version`
- `timestamp`
- `source_type`
- `source_ref`
- `raw_summary`
- `change_type`: added / modified / removed / replaced
- `previous_version`
- `status`: active / superseded
- `affected_memory`
- `implementation_status`
- `verification_status`

### 5.3 优先级

需求来源优先级：

1. 用户最新明确表达。
2. 用户明确指定采用的最新 PRD 或文档版本。
3. 已确认需求基线。
4. 旧 PRD、旧聊天记录和历史归档。
5. AI 建议和技术推测，不得自行提升为需求。

## 6. 首次业务建档流程

触发条件：项目仍处于 `[UNINITIALIZED]` 或没有需求基线，并收到真实需求来源。

流程：

1. 识别来源类型和版本。
2. 保存用户原话或源文件引用、摘要、字节数和 SHA-256。
3. 清洗业务需求，区分需求、事实、假设、技术建议和无效承诺。
4. 创建 `requirements/current.md` v1。
5. 追加 `change-log.jsonl` 初始事件。
6. 更新 `projectbrief.md` 的目标、范围和非目标。
7. 更新 `activeContext.md` 的需求版本、当前任务、下一步和风险。
8. 仅在确有长期价值时更新接口、架构和决策文件。
9. 运行健康检查并记录首次初始化 checkpoint。

首次建档不自动宣称代码已实现。

## 7. 需求变更同步流程

1. 判断输入是否为新的明确用户需求。
2. 与 `requirements/current.md` 比较，识别新增、修改、取消或替换。
3. 按 Latest User Intent Wins 更新当前基线。
4. 将旧版本标记为 `SUPERSEDED`，追加变更事件。
5. 计算影响路由：
   - 总体目标/范围 → `projectbrief.md`
   - 当前任务/下一步 → `activeContext.md`
   - API/数据/权限 → `interfaces.md`
   - 系统边界 → `architecture.md`
   - 长期取舍 → `decisionLog.md`
   - 取消/延期 → `backlog.md` 和任务账本
   - 验收变化 → 需求基线和任务包 Requirement Checklist
6. 更新相关文件，不重写无关文件。
7. 将受影响实现标记为 `IMPLEMENTATION_PENDING` 或 `REWORK`，不得保留虚假的 DONE。
8. 验证引用、版本、启动预算和状态一致性。

## 8. 上下文预算

`index.json` 增加机器可验证预算：

- startup max files: 3
- startup warn characters: 12,000
- startup hard max characters: 18,000
- index hard max characters: 4,000
- activeContext hard max characters: 6,000
- progress hard max characters: 12,000
- max single line characters: 2,000
- progress max records: 30

字符预算为跨语言主要限制；字节、行数和估算 token 作为附加指标。

## 9. 自动维护与迁移

新增工具：

- `memory-health.ps1`：报告启动体积、引用、需求版本、过期状态和归档完整性。
- `compact-memory.ps1`：默认 DryRun，原子归档超限内容并生成 manifest/SHA-256。
- `migrate-memory.ps1`：把旧项目升级到新模式，迁移前备份，可回滚。

任何归档和迁移必须先写临时目录、校验哈希，再替换活动文件。

## 10. 验收标准

1. 新项目首次收到需求后能够生成非空需求基线并更新项目记忆。
2. 用户新需求能够直接覆盖旧需求，不要求二次确认。
3. 旧需求仍可通过变更日志和归档追溯。
4. 需求变化只更新受影响的记忆文件。
5. 需求更新不会被误标为代码已完成。
6. 默认启动文件不超过三个。
7. 启动字符超限、单行超限或 activeContext 超限时 CI 必须失败。
8. 205KB 单行 activeContext 的回归场景必须被拒绝。
9. 压缩后归档哈希和来源内容守恒。
10. 旧项目迁移具有 DryRun、备份、验证和回滚能力。

## 11. 非目标

本轮不实现自然语言大模型分类服务，不引入数据库，不自动修改业务代码，不自动执行生产部署，也不构建复杂的全文向量检索系统。
