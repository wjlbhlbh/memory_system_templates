# 开源升格路线

本文档用于把本项目从“个人可用模板”升级为“别人愿意试用、理解、贡献、传播的开源项目”。

## 参考对象
- Cline Memory Bank：结构化 Markdown 记忆文件、跨会话接管、`projectbrief.md` / `activeContext.md` / `progress.md` 等核心文件分工清晰。参考：https://docs.cline.bot/features/memory-bank
- AGENTS.md 生态：根目录指令文件正在成为多 Agent 工具的稳定入口，适合承载启动顺序、测试命令、代码规范和安全边界。参考：https://github.com/openai/codex/blob/main/docs/agents_md.md
- MCP servers 仓库：成熟开源集合通常提供清晰分类、模板、贡献入口和生态链接。参考：https://github.com/modelcontextprotocol/servers
- AGENTS.md 研究提醒：上下文文件并非越多越好，过度规则会增加成本并可能降低任务成功率，因此本项目应坚持“短启动、强索引、按需展开”。参考：https://arxiv.org/abs/2602.11988

## 当前定位
本项目不是单一 prompt，而是一套面向 AI 编程协作的 Pro 级项目记忆模板：
- Pro：完整工程记忆，适合真实开发项目、长期项目、全栈项目、多人协作。
- 小项目也使用 Pro，只少填非必要字段，避免 Lite/Pro 分叉导致规则漂移。
- Tool adapters：为 Codex、Claude Code、OpenCode、Antigravity、Cursor、Cline、Roo Code 等工具生成入口文件。

## 已完成的升格动作
- 统一 Agent 可读文件为 UTF-8 无 BOM，降低 LLM 和工具读取异常概率。
- 增加无需外部依赖的验证脚本 `tests/verify-memory-system.ps1`。
- 增加 `.editorconfig`、`.gitattributes`、`.gitignore`，固定编码、换行与运行产物边界。
- 把“减少打扰的一口气交付”“自动提交推送”“源码与本地备份分层”写入 Pro 规则。
- 增加基础开源文件：`LICENSE`、`CONTRIBUTING.md`、`SECURITY.md`、`CHANGELOG.md`。
- 增加 GitHub Actions CI，自动验证模板完整性与编码规范。

## 下一阶段建议
1. 增加真实示例项目
   - `examples/minimal-script/`
   - `examples/fullstack-app/`
   - 每个示例给出初始化前后目录对比和一次完整 Agent 接管记录。

2. 增加安装方式
   - 发布 PowerShell 脚本下载命令。
   - 后续可增加 npm / pipx / winget 包装，让用户不用复制本地绝对路径。

3. 增加演示材料
   - README 顶部补 GIF 或终端录屏。
   - 展示“新会话读取记忆 -> 修改代码 -> 验证 -> 更新 progress -> 自动提交”的闭环。

4. 控制上下文成本
   - 不再维护 Lite 简版，避免双模板漂移。
   - Pro 文件超过 150 行时引导归档。
   - 新规则优先写进 `agentRules.md`，避免到处散落重复指令。

5. 增加跨平台验证
   - 当前重点是 Windows / PowerShell。
   - 后续补 `pwsh` 跨平台脚本，降低 macOS/Linux 用户门槛。

6. 明确项目品牌
   - 准备一个更容易传播的英文名，例如 `AI Memory Templates`、`Agent Memory System`。
   - README 首屏用一句话说明差异化：多工具入口、风险分级、验证闭环、低打扰交付。

7. 建立贡献路线
   - 标记适合新手的 issue：新增适配器、补示例、改文档、补跨平台测试。
   - 用 GitHub Discussions 收集不同 AI 工具的适配经验。

## 开源推广建议
- 第一波内容：写一篇中文文章，标题聚焦痛点，例如“我给 AI 编程做了一套不会断片的项目记忆系统”。
- 第二波内容：录 2 分钟演示视频，展示同一个项目在 Codex/Claude/Cline 间切换仍能接管。
- 第三波内容：把项目提交到相关话题和社区，标签建议：`ai-coding`、`agents-md`、`memory-bank`、`codex`、`claude-code`、`cline`、`developer-tools`。
