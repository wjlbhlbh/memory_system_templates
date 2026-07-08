# Changelog

## Unreleased
- 去除入口规则对具体文件工具 API 名称的依赖，改为使用当前环境可用的等价能力。
- 增加 mojibake/乱码规避规则和验证检查，要求记忆文件显式保持 UTF-8 可读。
- 将 `activeContext.md` / `progress.md` 优化为活跃窗口、滚动窗口和归档索引模式，降低超大型项目接手 token 成本。
- 增加 Fast startup：启动时只读取 `startup_order`，其余记忆文件按任务相关性加载。
- 移除 `activeContext.md` 中的示例 WIP，避免 Agent 误判为未闭合任务。
- 调整 L1 任务策略为默认直接执行，减少反复等待确认。
- 统一 Agent 可读文件为 UTF-8 无 BOM，降低跨工具读取异常概率。
- 增加 `tests/verify-memory-system.ps1`，验证编码、索引完整性和脚本生成结果。
- 收敛为 Pro-only 模板，删除 Lite 简版，减少规则分叉和维护漂移。
- 增强 Pro 规则：减少打扰的一口气交付、自动提交推送、源码与本地备份分层、文件编码完整性。
- 增加 `.gitignore`、`.editorconfig`、`.gitattributes` 和 GitHub Actions CI。
- 增加开源协作文件：`CONTRIBUTING.md`、`SECURITY.md`、`LICENSE`、`docs/OPEN_SOURCE_UPGRADE.md`。
