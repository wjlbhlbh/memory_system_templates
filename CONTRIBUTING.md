# Contributing

欢迎贡献适配器、示例、文档和验证脚本。这个项目的核心目标是让 AI 编程协作更稳定、更可验证、更容易跨工具接管。

## 开发前
1. 阅读 `README.md` 和 `docs/OPEN_SOURCE_UPGRADE.md`。
2. 如果修改模板内容，统一维护 `.ai_memory-pro`，不要重新引入 Lite/Pro 双模板分叉。
3. 不要把本地备份、日志、数据库、缓存或测试输出提交到仓库。

## 质量要求
- Agent 可读文件必须是 UTF-8 无 BOM。
- 修改 `.ai_memory-*` 后，确认 `index.json` 的 `bootstrap_order` 不引用缺失文件。
- 修改初始化或同步脚本后，必须运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\verify-memory-system.ps1
```

## 提交建议
- 提交信息尽量说明真实改动，例如：`增强记忆规则与编码校验`。
- 一个 PR 聚焦一个主题，避免把规则、脚本、文档、格式化混在一起。
- 如果新增工具适配器，请说明该工具的入口文件位置和启动规则来源。
