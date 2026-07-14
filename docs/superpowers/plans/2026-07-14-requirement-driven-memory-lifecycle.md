# Requirement-Driven Memory Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将模板升级为三文件预算化启动、首次需求建档、最新用户需求直接覆盖、可审计变更、可验证压缩和旧项目迁移的记忆生命周期系统。

**Architecture:** `.ai_memory/index.json` 只负责机器路由和预算；`projectbrief.md` 与 `activeContext.md` 构成启动载荷。`requirements/current.md` 保存当前有效需求，`requirements/change-log.jsonl` 保存追加式事件；AI 负责语义理解，PowerShell 工具负责确定性写入、预算检查、归档哈希和迁移。

**Tech Stack:** PowerShell 5.1+、Markdown、JSON、JSONL、GitHub Actions 现有验证流程。

---

## 文件结构

**新增：**

- `.ai_memory-pro/requirements/current.md`：当前需求基线模板。
- `.ai_memory-pro/requirements/change-log.jsonl`：需求事件 schema seed。
- `memory-health.ps1`：目标项目记忆健康检查和预算报告。
- `record-requirement-change.ps1`：按 Requirement ID 直接覆盖当前基线并追加审计事件。
- `compact-memory.ps1`：安全归档原文件并原子应用压缩替换。
- `migrate-memory.ps1`：旧 `.ai_memory` 升级、备份和 DryRun。

**修改：**

- `.ai_memory-pro/index.json`：三文件启动、预算、需求生命周期和按需路由。
- `.ai_memory-pro/activeContext.md`：增加需求基线版本并缩短静态规则。
- `.ai_memory-pro/agentRules.md`：首次需求建档和 Latest User Intent Wins。
- `.ai_memory-pro/MEMORY.md`：退出默认启动，保留短导航。
- `.ai_memory-pro/history/index.jsonl`：扩展归档字段。
- `init-memory.ps1`：复制新增工具并生成需求目录。
- `search-memory.ps1`：增加任务、类型、日期、数量和哈希过滤。
- `tool_adapters/*.template.md`：统一三文件启动和需求同步触发。
- `tests/verify-memory-system.ps1`：增加预算、需求、工具和回归测试。
- `README.md`、`docs/CONTINUOUS_DEVELOPMENT_PROTOCOL.md`、`CHANGELOG.md`：记录新生命周期。

### Task 1: 用失败测试锁定三文件启动和真实体积预算

**Files:**
- Modify: `tests/verify-memory-system.ps1`
- Test: `tests/verify-memory-system.ps1`

- [ ] **Step 1: 增加预算读取和断言测试**

在验证脚本中加入：

```powershell
function Get-TextMetrics {
    param([string]$Path)
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    return [pscustomobject]@{
        Bytes = (Get-Item -LiteralPath $Path).Length
        Characters = $text.Length
        Lines = ($text -split "`r?`n").Count
        MaxLineCharacters = (($text -split "`r?`n" | ForEach-Object { $_.Length }) | Measure-Object -Maximum).Maximum
    }
}
```

验证：`startup_order.Count -eq 3`、不存在完整 `bootstrap_order`、启动总字符、单文件字符和单行字符均不超预算。

- [ ] **Step 2: 增加 205KB 单行回归夹具**

生成临时项目后追加：

```powershell
[IO.File]::AppendAllText(
    (Join-Path $tempRoot ".ai_memory\activeContext.md"),
    ("X" * 200000),
    [Text.UTF8Encoding]::new($false)
)
```

运行健康检查必须返回非零，并包含 `activeContext hard character budget exceeded` 或 `single-line budget exceeded`。

- [ ] **Step 3: 运行测试确认失败**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\verify-memory-system.ps1
```

Expected: FAIL，因为当前 `startup_order` 有五个文件且没有字符预算。

### Task 2: 收敛索引与启动胶囊

**Files:**
- Modify: `.ai_memory-pro/index.json`
- Modify: `.ai_memory-pro/activeContext.md`
- Modify: `.ai_memory-pro/MEMORY.md`
- Modify: `.ai_memory-pro/agentRules.md`

- [ ] **Step 1: 将索引升级到 2.0.0**

使用以下核心结构：

```json
{
  "version": "2.0.0",
  "memory_system": "professional-project-memory-lifecycle",
  "startup_order": ["index.json", "projectbrief.md", "activeContext.md"],
  "budgets": {
    "startup": {"max_files": 3, "warn_characters": 12000, "hard_max_characters": 18000, "estimated_token_limit": 6000},
    "index": {"hard_max_characters": 4000},
    "active_context": {"hard_max_characters": 6000, "hard_max_lines": 90, "max_single_line_characters": 2000},
    "progress": {"hard_max_characters": 12000, "hard_max_lines": 120, "max_records": 30}
  }
}
```

删除 `bootstrap_order`，把完整清单改为 `memory_catalog` 或通过 `file_roles` 表达。

- [ ] **Step 2: 缩短 activeContext 静态说明**

只保留动态字段：状态、需求基线版本、任务、阶段、最新 checkpoint、未验证工作、Resume Reads、风险和 Requirement Checklist。

- [ ] **Step 3: 明确 MEMORY/agentRules 为按需文件**

`MEMORY.md` 继续作为人工导航，但不进入启动顺序；`agentRules.md` 只在详细治理规则需要时读取。

- [ ] **Step 4: 运行验证**

Expected: 三文件和预算结构检查通过，其他新增生命周期测试仍失败。

### Task 3: 增加需求基线和变更日志模板

**Files:**
- Create: `.ai_memory-pro/requirements/current.md`
- Create: `.ai_memory-pro/requirements/change-log.jsonl`
- Modify: `.ai_memory-pro/index.json`
- Modify: `.ai_memory-pro/activeContext.md`
- Modify: `tests/verify-memory-system.ps1`

- [ ] **Step 1: 写需求生命周期失败测试**

检查：

```powershell
Assert-True (Test-Path (Join-Path $MemoryPath "requirements\current.md")) "Missing requirements/current.md"
Assert-True (Test-Path (Join-Path $MemoryPath "requirements\change-log.jsonl")) "Missing requirements/change-log.jsonl"
```

并要求 current 模板包含 `baseline_version`、`[UNINITIALIZED]`、稳定 Requirement ID、实现状态和验证状态。

- [ ] **Step 2: 创建当前基线模板**

初始元数据：

```markdown
- **state**: [UNINITIALIZED]
- **baseline_version**: 0
- **updated_at**: __DATE__
- **latest_source**: none
```

定义目标、有效需求、业务规则、角色权限、非目标、验收标准和 superseded 索引。

- [ ] **Step 3: 创建 JSONL schema seed**

```json
{"event_id":"schema","requirement_id":"REQ-000","version":0,"timestamp":"__DATE__","source_type":"schema","source_ref":"requirements/README","raw_summary":"Schema seed","change_type":"added","previous_version":null,"status":"schema","affected_memory":[],"implementation_status":"not_applicable","verification_status":"not_applicable"}
```

- [ ] **Step 4: 将需求文件加入 semantic/episodic 分类和按需路由**

确保它们不进入 `startup_order`，但首次建档和需求变化时必须读取。

### Task 4: 实现确定性的需求覆盖工具

**Files:**
- Create: `record-requirement-change.ps1`
- Modify: `tests/verify-memory-system.ps1`

- [ ] **Step 1: 写 latest-wins 失败测试**

调用：

```powershell
& .\record-requirement-change.ps1 -MemoryPath $memoryPath -RequirementId REQ-001 -Title "删除权限" -Statement "普通用户可直接删除" -SourceType user -SourceRef "turn-1"
& .\record-requirement-change.ps1 -MemoryPath $memoryPath -RequirementId REQ-001 -Title "删除权限" -Statement "普通用户提交申请，由管理员审核" -SourceType user -SourceRef "turn-2"
```

断言 current 中只存在第二个 active statement；JSONL 同时保留 v1 superseded 和 v2 active 事件；实现状态为 `implementation_pending`。

- [ ] **Step 2: 实现参数和原子写入**

脚本参数：

```powershell
param(
  [string]$MemoryPath = ".ai_memory",
  [Parameter(Mandatory)][ValidatePattern('^REQ-\d{3,}$')][string]$RequirementId,
  [Parameter(Mandatory)][string]$Title,
  [Parameter(Mandatory)][string]$Statement,
  [ValidateSet('added','modified','removed','replaced')][string]$ChangeType = 'modified',
  [string]$SourceType = 'user',
  [string]$SourceRef = 'direct-user-expression',
  [string[]]$AffectedMemory = @('requirements/current.md','activeContext.md')
)
```

使用临时文件和 `Move-Item` 原子替换；按相同 ID 递增版本；旧事件不改写，通过新事件的 `previous_version` 和当前 baseline 的 superseded 索引表达取代关系。

- [ ] **Step 3: 更新 activeContext 需求版本**

脚本把 `baseline_version` 和最新需求事件写入 activeContext 的机器管理字段，不把实现状态标成 DONE。

- [ ] **Step 4: 运行覆盖、删除和特殊字符测试**

Expected: 最新用户表达直接生效，旧事件可追溯，UTF-8 中文保持可读。

### Task 5: 首次需求建档和影响传播规则

**Files:**
- Modify: `.ai_memory-pro/agentRules.md`
- Modify: `.ai_memory-pro/projectbrief.md`
- Modify: `.ai_memory-pro/activeContext.md`
- Modify: `tool_adapters/*.template.md`
- Modify: `docs/CONTINUOUS_DEVELOPMENT_PROTOCOL.md`
- Modify: `tests/verify-memory-system.ps1`

- [ ] **Step 1: 测试所有入口包含首次建档触发**

要求入口文本包含 `requirements/current.md`、`UNINITIALIZED`、`Latest User Intent Wins`、`SUPERSEDED` 和“需求同步不等于实现完成”。

- [ ] **Step 2: 增加首次建档协议**

收到首份需求或 PRD 时，Agent 必须先建立 baseline、更新 projectbrief/activeContext，再进入实施；保存源文件引用、摘要和 SHA-256，不把大文档复制到启动胶囊。

- [ ] **Step 3: 增加选择性影响传播表**

明确总体目标、接口权限、架构、决策、取消延期和验收变化分别更新哪些文件；无关文件不得重写。

- [ ] **Step 4: 增加需求/实现状态分离检查**

模板必须同时显示 `implementation_status` 和 `verification_status`，且首次需求同步默认不是 DONE。

### Task 6: 实现 memory-health.ps1

**Files:**
- Create: `memory-health.ps1`
- Modify: `init-memory.ps1`
- Modify: `tests/verify-memory-system.ps1`

- [ ] **Step 1: 写健康报告失败测试**

验证正常项目输出：

```text
Startup files: 3 / limit 3
Requirements baseline: 0 [UNINITIALIZED]
Overall status: PASS
```

超限项目返回 exit code 1 并输出具体预算错误。

- [ ] **Step 2: 实现预算和引用检查**

读取 `index.json.budgets`，计算 bytes、characters、lines、max line、估算 token；验证 startup、Resume Reads、requirements JSONL 和 history JSONL。

- [ ] **Step 3: init 时复制健康工具**

目标项目根目录生成 `memory-health.ps1`，不覆盖已有同名文件。

### Task 7: 实现安全压缩归档

**Files:**
- Create: `compact-memory.ps1`
- Modify: `tests/verify-memory-system.ps1`

- [ ] **Step 1: 写 DryRun 和 Apply 失败测试**

DryRun 不修改文件；Apply 接收 `-ActiveContextReplacementPath` / `-ProgressReplacementPath`，归档原始字节并应用满足预算的新文件。

- [ ] **Step 2: 实现归档事务**

流程：临时目录 → 复制原文件 → SHA-256 → manifest → 验证替换文件 → 原子替换 → 更新 history/index.jsonl → 设置只读。失败时恢复原文件并删除未提交临时目录。

manifest 至少包含：archive_version、created_at、branch、head、source_path、archive_path、bytes、characters、lines、sha256、preservation。

- [ ] **Step 3: 增加哈希篡改测试**

修改归档文件后，`memory-health.ps1 -VerifyArchive` 必须失败。

### Task 8: 实现旧项目迁移

**Files:**
- Create: `migrate-memory.ps1`
- Modify: `tests/verify-memory-system.ps1`

- [ ] **Step 1: 写旧 1.2.0 项目迁移测试**

DryRun 只输出：将备份、将增加 requirements、将收敛 startup_order、发现的超限文件；不修改磁盘。

- [ ] **Step 2: 实现 Apply**

备份旧 `.ai_memory` 到 `.ai_memory_archive/migration-<timestamp>` 并生成 manifest；保留项目内容，升级索引版本和预算，增加缺失需求文件，不擅自压缩含业务信息的 activeContext/progress。

- [ ] **Step 3: 验证幂等和回滚资料**

第二次 Apply 不重复迁移；manifest 提供恢复来源；迁移后运行 memory-health。

### Task 9: 检索、初始化和文档收口

**Files:**
- Modify: `search-memory.ps1`
- Modify: `init-memory.ps1`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `ROADMAP.md`
- Test: `tests/verify-memory-system.ps1`

- [ ] **Step 1: 扩展搜索参数**

增加 `-TaskId`、`-Type`、`-Since`、`-Limit`、`-VerifyHash`，并验证结果 path 存在。

- [ ] **Step 2: 初始化时复制所有运行工具**

生成 `search-memory.ps1`、`memory-health.ps1`、`record-requirement-change.ps1`、`compact-memory.ps1`、`migrate-memory.ps1`，已有文件则拒绝覆盖并给出明确错误。

- [ ] **Step 3: 更新文档**

补充首次建档、最新用户需求覆盖、需求版本、三层记忆、健康检查、压缩和迁移示例。

- [ ] **Step 4: 运行完整验证**

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\verify-memory-system.ps1
```

Expected: `Memory system verification passed.`

- [ ] **Step 5: 检查差异**

```powershell
git diff --check
git status --short
```

Expected: 无空白错误，只有本功能相关文件发生变化。