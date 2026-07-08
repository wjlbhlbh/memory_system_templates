# AI Memory System Templates

这套模板用于给新项目初始化 `.ai_memory`，目标不是只提供目录结构，而是提供一套可直接复用的规则内容设计。

## 它解决什么问题

AI 编程最常见的失控点不是“不会写代码”，而是上下文断片、文件没读全、凭印象改代码、没有验证就宣称完成、换工具后没人知道上次做到哪。

本项目把这些协作纪律沉淀为一套轻量模板：
- 新会话先读 `.ai_memory/index.json`，再只读 `startup_order` 指定的启动文件。
- 其他记忆文件按任务需要再读取，避免每次启动都消耗大量上下文。
- 在真正编码前，先把用户原话翻译成“真实意图 / 成功标准 / 明确非目标 / 风险级别”。
- 任务按 L0/L1/L2/L3 分级，明确哪些能自动推进、哪些必须确认。
- 每次完成都要有真实验证证据，并同步 `progress.md`。
- 长任务按 verified checkpoint 持续写回，`activeContext.md` 负责当前状态，`progress.md` 负责已验证事实。
- 多 LLM / 多 Agent / 跨模块任务进入 `masterTaskLedger.md`，按任务认领、锁定文件、记录验证证据和交接要点。
- 复杂任务用 `task-packs/` 做单任务上下文包，明确 required reading、do not read、acceptance、Requirement Checklist 和 handoff。
- 长期历史、旧日志和过期交接进入 `history/`，避免启动文件和进度文件越来越臃肿。
- 默认支持“减少打扰的一口气交付”：小决策由 Agent 保守判断，除硬性阻塞外持续推进。
- 上下文压缩、模型切换、工具切换后，先根据 `activeContext.md` 恢复最近 checkpoint，而不是重新猜前文。
- 默认执行源码提交与本地备份分层：源码进 Git，备份进 `.archive/`，运行产物进 `.gitignore`。
- 入口规则不绑定具体工具 API 名称；Agent 使用当前环境可用的等价文件读取、搜索、编辑和写入能力。
- Agent 可读文件统一使用 UTF-8 无 BOM；如出现 mojibake/乱码，先修复可读性再继续业务改动。

## 最少人工步骤

推荐直接运行根目录脚本 `init-memory.ps1`，它会自动：
- 复制 Pro 模板到目标项目根目录
- 自动写入项目名、项目路径、当前日期、操作系统、默认终端
- 自动探测常见技术栈线索（如 `package.json`、`requirements.txt`、`pyproject.toml`、`pom.xml`、`Cargo.toml`）
- 自动从项目文件中提取常见运行时版本要求（如 `.python-version`、`pyproject.toml`、`package.json engines`、`.nvmrc`、`Dockerfile`、`pom.xml`、`rust-toolchain`）
- 生成 `.ai_memory/SETUP_TODO.md`，把你真正还需要补的内容压缩成少量条目

这样你不需要自己逐个文件手工改一遍。
稳定不变的宿主机信息默认只在初始化时自动写入一次，不要求你在每个新项目里反复手填或维护。
像“Windows / PowerShell”这类信息只是运行背景；像 Python 版本、Node 版本这类信息，只有在项目对版本敏感时才值得记录，而且应优先记录项目要求，不是你个人机器的全局安装情况。

## 模板说明

### `.ai_memory-pro`
- 适合真实开发项目、长期项目、多人协作项目、全栈项目、需要交接的项目
- 重点解决：断点接管、长期决策追踪、待办债务收敛、接口漂移控制、踩坑复发控制
- 优点：完整、稳定、适合长期积累；避免简版/专业版分叉造成维护漂移
- 取舍：小项目也默认使用 Pro，但只维护必要字段即可

## 推荐选择
- 所有新项目默认使用 Pro。
- 单文件脚本、小型 Demo 可以少填字段，但不再维护单独简版模板。
- 有后端 / 前端 / 数据库 / 部署 / 测试链路或长期商业项目时，完整维护 Pro 文件。

## 工具接入
`tool_adapters/` 目录里提供了不同 AI 工具的入口模板。核心思想一致：

1. 任何新会话必须先读取 `.ai_memory/index.json`
2. 再读取 `startup_order` 中列出的启动文件
3. 其他记忆文件只在与当前任务、目标模块、接口、架构、历史决策、待办、踩坑或验证路径相关时按需读取
4. 完成快速启动后，L0/L1 任务应直接进入实质开发，只有 L2/L3 或硬性阻塞才停下来确认

不是把整个 `tool_adapters/` 文件夹复制进新项目。
默认推荐做法是：在项目根目录同时准备好 `AGENTS.md` 和 `CLAUDE.md`，把常见工具入口一次配齐。
这样后面切到 Codex、OpenCode、Antigravity、Claude Code 时，不需要再想起手工补入口文件。

## 针对实战问题的强化

最近模板补强了 4 个容易失控的点：

1. **模糊需求先翻译，不允许直接按字面编码**
   - 先写清用户原话、真实意图、成功标准、明确非目标。
   - 用户不是程序员很正常，Agent 不能因为表述不专业就擅自扩需求。
   - 只有歧义不影响行为边界时，才允许保守假设继续。

2. **先锁定“禁止误伤项”，再动代码**
   - 修改前先识别不应被破坏的模块、页面、接口、数据流、测试口径。
   - 验证前不得宣称“只影响这里”。

3. **连续开发按 checkpoint 写回，不等最后一次性补记忆**
   - `activeContext.md` 保存当前 WIP、阶段、恢复锚点、多 Agent 分工。
   - `progress.md` 只写已验证通过的 checkpoint。
   - 长任务必须拆成多个小闭环，否则上下文压缩后一定会反复重走前戏。

4. **上下文压缩 / 切模型后，先恢复再继续**
   - 重新读取 `index.json + startup_order`。
   - 再读取 `activeContext.md` 中列出的恢复必读文件。
   - 从最近 verified checkpoint 接着做，而不是重新靠聊天记忆拼接。

5. **多 LLM 交替开发用全局任务账本**
   - `masterTaskLedger.md` 只记录任务索引、状态、依赖、locked files、verification evidence 和交接要点。
   - 每个任务必须拆到一次会话能独立交付和验证的粒度。
   - 子 Agent 不直接写主记忆，由主 Agent 汇总后写回。

6. **复杂任务用任务上下文包，不靠全量读记忆**
   - `task-packs/*.md` 明确本任务 required reading 和 do not read。
   - 完成前必须输出 Requirement Checklist，逐条对应需求、实现状态和验证证据。
   - `activeContext.md` 只保留活跃窗口，`progress.md` 只保留滚动窗口和归档索引。
   - 旧日志、长交接和过期细节移入 `history/`，防止 `activeContext.md` / `progress.md` 变成大杂烩。

更完整的连续开发协议见 [docs/CONTINUOUS_DEVELOPMENT_PROTOCOL.md](docs/CONTINUOUS_DEVELOPMENT_PROTOCOL.md)。

### 常见工具与生效位置

| 工具 | 模板文件 | 新项目中实际文件名 | 放置位置 | 说明 |
|---|---|---|---|---|
| Codex | `tool_adapters/CODEX.template.md` | `AGENTS.md` | 仓库根目录 | Codex 使用 `AGENTS.md` |
| OpenCode | `tool_adapters/OPENCODE.template.md` | `AGENTS.md` | 仓库根目录 | OpenCode 使用 `AGENTS.md` |
| Antigravity | `tool_adapters/ANTIGRAVITY.template.md` | `AGENTS.md` | 仓库根目录 | 当前公开资料显示可走 `AGENTS.md` |
| 通用 AGENTS 生态工具 | `tool_adapters/AGENTS.md.template` | `AGENTS.md` | 仓库根目录 | 适用于支持 AGENTS.md 的工具 |
| Claude Code | `tool_adapters/CLAUDE.md.template` | `CLAUDE.md` | 仓库根目录 | Claude Code 的项目级入口文件 |
| Cursor | `tool_adapters/CURSOR.template.md` | 按 Cursor 项目规则入口落地 | 通常在仓库根目录 | 这里提供的是接入提示模板 |
| Cline | `tool_adapters/CLINE.template.md` | 按 Cline 项目规则入口落地 | 通常在仓库根目录 | 这里提供的是接入提示模板 |
| Roo Code | `tool_adapters/ROO_CODE.template.md` | 按 Roo Code 项目规则入口落地 | 通常在仓库根目录 | 这里提供的是接入提示模板 |

### 最简单的使用方式

1. 先运行 `init-memory.ps1` 生成 `.ai_memory/`
2. 默认让脚本同时生成 `AGENTS.md` 和 `CLAUDE.md`
3. 只有你明确想精简时，才只生成单个入口文件

例如：

- 用默认推荐方式：运行初始化脚本，不额外传 `-Adapter`，会自动生成 `AGENTS.md` 和 `CLAUDE.md`
- 用 Codex / OpenCode / Antigravity 专用方式：传 `-Adapter CODEX` 或 `-Adapter OPENCODE` 或 `-Adapter ANTIGRAVITY`
- 用 Claude Code 专用方式：传 `-Adapter CLAUDE`

## 使用方式
1. 进入新项目根目录
2. 运行：

```powershell
powershell -ExecutionPolicy Bypass -File D:\AIbiancheng\memory_system_templates\init-memory.ps1 -Mode Pro
```

默认情况下，脚本会自动生成 `AGENTS.md` 和 `CLAUDE.md` 两个常用入口文件：

```powershell
powershell -ExecutionPolicy Bypass -File D:\AIbiancheng\memory_system_templates\init-memory.ps1 -Mode Pro
```

如果你想只生成某一个工具入口文件，也可以显式指定 `-Adapter`：

```powershell
powershell -ExecutionPolicy Bypass -File D:\AIbiancheng\memory_system_templates\init-memory.ps1 -Mode Pro -Adapter CODEX
```

或：

```powershell
powershell -ExecutionPolicy Bypass -File D:\AIbiancheng\memory_system_templates\init-memory.ps1 -Mode Pro -Adapter CLAUDE
```

3. 打开新生成的 `.ai_memory/SETUP_TODO.md`
4. 只补最少几个业务字段
5. 默认情况下，项目根目录已经自动生成 `AGENTS.md` 和 `CLAUDE.md`
6. 如果是老项目或你想补入口文件，可运行 `sync-tool-adapters.ps1`

例如：

```powershell
powershell -ExecutionPolicy Bypass -File D:\AIbiancheng\memory_system_templates\sync-tool-adapters.ps1 -TargetPath .
```

## 如果不想用脚本
你也可以手动复制 `.ai_memory-pro` 到项目根目录并重命名为 `.ai_memory`，但这会增加人工维护量，不建议作为默认方式。

## 一口气开发模式

你可以把下面这段作为默认任务风格，模板里的 `agentRules.md` 已经内置同类规则，不需要每次重复强调：

```text
不用再向我确认小决策，你自行做合理假设并继续推进。
先按 .ai_memory/index.json 的 startup_order 完成快速启动，再读取和任务直接相关的文件。
修改代码、补测试、运行验证、按需更新记忆一次做完。
除非遇到无法自行解决的硬性阻塞，例如缺少密钥、外部平台权限、必须人工扫码/发布、生产不可逆操作，否则不要停下来问我。
完成后给我最终总结：改了什么、验证结果、哪些产品判断由你代做、还剩什么需要我手工确认。
默认以“减少打扰优先”模式工作，遇到非关键分支直接替我做产品判断。
严禁对其他板块、页面、接口或已有流程造成影响。
```

## 质量验证

本仓库提供一个无需外部依赖的验证脚本，用来检查：
- Agent 可读文件是否为严格 UTF-8 无 BOM。
- Agent 可读文件是否出现疑似 mojibake/乱码。
- Pro 的 `index.json` 是否能解析。
- `startup_order` / `bootstrap_order` 是否引用了真实存在的文件。
- 启动规则是否避免全量读取记忆文件，并引导 Agent 快速进入开发。
- 启动规则和工具入口模板是否避免绑定具体文件工具 API 名称。
- `activeContext.md` / `progress.md` 是否具备活跃窗口、滚动窗口和归档索引规则。
- 多 LLM 协作所需的 `masterTaskLedger.md`、`task-packs/README.md`、`history/README.md` 是否存在且包含关键规则。
- 工具入口模板是否要求 Startup Summary 和 Requirement Checklist。
- `init-memory.ps1` 和 `sync-tool-adapters.ps1` 生成的文件是否符合编码要求。

运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\verify-memory-system.ps1
```

GitHub Actions 也会运行同一套验证。

## 开源化路线

本项目已补充 `LICENSE`、`CONTRIBUTING.md`、`SECURITY.md`、`CHANGELOG.md`、CI 与开源升级建议。详细路线见：

- `docs/OPEN_SOURCE_UPGRADE.md`
