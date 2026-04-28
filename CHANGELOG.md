# Changelog

## Unreleased
- 统一 Agent 可读文件为 UTF-8 无 BOM，降低跨工具读取异常概率。
- 增加 `tests/verify-memory-system.ps1`，验证编码、索引完整性和脚本生成结果。
- 收敛为 Pro-only 模板，删除 Lite 简版，减少规则分叉和维护漂移。
- 增强 Pro 规则：减少打扰的一口气交付、自动提交推送、源码与本地备份分层、文件编码完整性。
- 增加 `.gitignore`、`.editorconfig`、`.gitattributes` 和 GitHub Actions CI。
- 增加开源协作文件：`CONTRIBUTING.md`、`SECURITY.md`、`LICENSE`、`docs/OPEN_SOURCE_UPGRADE.md`。
