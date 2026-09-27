# 可复用模板

`model-calling` 是统一模型调用功能的模板源文件，默认使用当前 Codex 助手交接模式。
它不是独立运行目录；通过以下命令导出完整、可发布的仓库目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./engine/export-model-template.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./engine/work/model-calling-template/tests/test.ps1
```

默认导出到被 Git 忽略的 `engine/work/model-calling-template`。指定 `-Destination` 可更换目录；
为了保护已有文件，目标目录必须不存在。导出器按白名单复制适配器、模板文件和 MIT 许可证，
不复制书稿、环境密钥、运行日志、现有模型私有配置或 Git 历史。

导出包使用原始 `engine/00-llm.ps1`，避免维护另一份分叉的调用实现。
模板源码修改后需导出到新目录再测试。发布仓库和启用 GitHub 模板属性是单独的步骤。
