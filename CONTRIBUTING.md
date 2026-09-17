# Contributing

欢迎贡献适配器、示例、文档和验证脚本。这个项目的核心目标是让 AI 编程协作更稳定、更可验证、更容易跨工具接管。

## 适合贡献什么
- 新 AI coding tool adapter：Codex、Claude Code、Cursor、Cline、OpenCode、Roo Code、Antigravity 之外的工具入口。
- 示例项目：minimal script、full-stack app、monorepo、开源项目维护场景。
- 文档改进：Quick Start、FAQ、迁移指南、中文/英文说明。
- 验证规则：编码、索引完整性、敏感信息、历史归档、模块记忆、任务包生命周期。
- 真实使用反馈：哪些规则减少了 token，哪些规则让 Agent 更稳，哪些地方仍然打扰过多。

## 开发前
1. 阅读 `README.md`、`ROADMAP.md`、`SUPPORT.md` 和 `docs/OPEN_SOURCE_UPGRADE.md`。
2. 如果修改模板内容，统一维护 `.ai_memory-pro`，不要重新引入 Lite/Pro 双模板分叉。
3. 不要把本地备份、日志、数据库、缓存或测试输出提交到仓库。

## 质量要求
- Agent 可读文件必须是 UTF-8 无 BOM。
- 修改 `.ai_memory-*` 后，确认 `index.json` 的 `startup_order` 只包含 `activeContext.md`，且不存在旧 `bootstrap_order`。
- 不要把 `index.json`、`projectbrief.md` 或其他文件加入启动载荷；复杂上下文通过精确任务包和 Resume Reads 按需读取。
- 修改初始化或同步脚本后，必须运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\memory-health.ps1 -MemoryPath .\.ai_memory-pro
powershell -ExecutionPolicy Bypass -File .\tests\verify-memory-system.ps1
```

## 提交建议
- 提交信息尽量说明真实改动，例如：`增强记忆规则与编码校验`。
- 一个 PR 聚焦一个主题，避免把规则、脚本、文档、格式化混在一起。
- 如果新增工具适配器，请说明该工具的入口文件位置和启动规则来源。
- 如果新增关键词、README 首屏或推广文案，请确保内容真实可验证，不夸大能力。

## 开源传播
- 欢迎分享你如何在 AI agent memory、Memory Bank、context engineering、Codex、Claude Code、Cursor、Cline 或 AGENTS.md 工作流中使用本项目。
- 欢迎在 Discussions 中发布真实案例，但请删去密钥、私有日志、客户数据和完整生产配置。
