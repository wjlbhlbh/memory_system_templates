# Memory Bootstrap For Roo Code

本项目的长期记忆入口不是单一 prompt，而是根目录 `.ai_memory/`。

强制规则：
1. 读取 `.ai_memory/projectbrief.md`
2. 读取 `.ai_memory/activeContext.md`
3. 读取 `.ai_memory/index.json`
4. 按 `bootstrap_order` 读取剩余记忆文件
5. 发现已有 `[WIP]` 时先接管，不得直接另开新任务
6. 任何编辑前必须重新读取目标文件
7. 没有真实运行证据，不得标记 `[DONE]`
