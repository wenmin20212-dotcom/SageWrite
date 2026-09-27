# 统一模型调用模板

从 SageWrite 提取的 PowerShell 文本生成适配层。多个脚本共用一个配置文件，
既能连接 API，也能把任务交给当前 Codex 助手完成。默认不调用 API、不消耗 API 密钥。
本模板不包含 SageWrite 的书稿、目录生成、审稿或排版系统。

## 快速开始

需要 Windows PowerShell 5.1 或 PowerShell 7。以下命令在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./run.ps1
```

默认读取 `prompt.md`。第一次运行打印 `SAGE_AGENT_PENDING` 和请求文件路径，
以退出码 2 表示等待助手，不产生结果文件。请在当前助手会话中授权其完成该请求。
助手读取请求，在同目录写入 `response.json`，再运行完全相同的命令。
验证通过后，结果保存为 `output/result.md`。已有结果不会被自动覆盖，需另选路径或显式使用 `-Force`。

```json
{
  "request_id": "复制 request.json 中的 request_id",
  "provider": "codex_agent",
  "status": "completed",
  "text": "实际完成的文本；JSON任务在此字段中放序列化后的JSON字符串"
}
```

请求默认保存在 `engine/work/agent_requests/<sha256>/`。哈希包含提示词、系统提示词和
输出预算；相同输入复用相同响应。需要重新生成时，仅归档该请求的响应后重跑。
这不是后台自动唤醒服务，必须有正在工作的助手处理交接。

## 一个配置入口

所有使用适配层的文本脚本读取 `engine/llm-config.json`。
优先级：环境变量 > 配置文件 > 适配器默认值。
`SAGE_LLM_CONFIG` 可以指向另一个 JSON 配置文件。
只改共享配置即可影响这些调用，但已有环境变量及显式的逐次模型覆盖仍优先。

| provider | 执行方式 | 必要条件 |
| --- | --- | --- |
| `codex_agent` | 当前助手通过文件交接完成任务 | 活跃、已获授权的助手会话 |
| `codex` | 启动独立的 `codex exec` 进程 | 已安装并完成认证的 Codex CLI |
| `openai` | HTTP Responses API | API 密钥和可用模型 |
| `openai-compatible` | HTTP Chat Completions 兼容接口 | 服务地址、密钥和该服务的模型 |

`codex_agent` 是执行模式，不是模型名称。设置 `SAGE_LLM_MODEL` 不能更换当前会话的模型。
Work Buddy 等其他助手的集成没有实现或验证。此模块仅处理文本，不处理图片 API。

例如将共享配置改为 API 模式，模型名称使用你实际有权调用的模型：

```json
{
  "SAGE_LLM_PROVIDER": "openai",
  "SAGE_LLM_MODEL": "YOUR_ACCESSIBLE_MODEL",
  "SAGE_LLM_API_STYLE": "responses"
}
```

密钥仅通过本地环境变量 `SAGE_LLM_API_KEY` 或兼容的 `OPENAI_API_KEY` 提供，勿提交到 Git。
兼容服务另设 `SAGE_LLM_BASE_URL` 和 `SAGE_LLM_API_STYLE: "chat-completions"`。
切换 provider 时应清除不再适用的环境覆盖和 API style 设置。
本模块不自动加载 `.env`。

可选变量：`SAGE_LLM_SYSTEM_PROMPT`、`SAGE_LLM_TIMEOUT_SEC`（HTTP超时）、
`SAGE_LLM_AGENT_REQUEST_ROOT`、`SAGE_LLM_CODEX_COMMAND`、`SAGE_LLM_CODEX_WORKDIR`。
当前 CLI 分支没有进程超时；交接预算是提示约束，不是对当前助手的硬性 token 限制。
本适配层返回文本，不提供完整的计费或 token 用量统计。

## 接入自己的脚本

```powershell
. "$PSScriptRoot/engine/00-llm.ps1"
$Text = Invoke-SageLlmText -Prompt 'Your authorized task' -MaxOutputTokens 2000
# Save only after the call returns successfully.
```

上层脚本应区分等待交接和真正错误，并负责业务格式校验、审阅及最终保存。
基础交接检查只验证请求编号、provider、完成状态和非空文本，不证明事实准确或业务 JSON 合法。
不要把私密材料提交到公开仓库；请求文件会包含完整提示词。

## 测试与发布

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/test.ps1
```

测试离线运行，禁止真实 HTTP 和 CLI 调用。GitHub Actions 在 Windows PowerShell 和
PowerShell 7 下运行同样的测试。真实 API 和 CLI 认证仍需自行集成验证。

将此导出的目录发布为自己的 GitHub 仓库后，在仓库设置中启用 **Template repository**。
此属性由 GitHub 管理，放入某个本地文件不会自动启用。
参见 [GitHub 官方模板仓库说明](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-template-repository)。
使用该仓库的 **Use this template** 创建新项目后，修改提示词和共享配置即可开始。

MIT 许可证；适配器源自 SageWrite。模板导出时复制原始适配器和许可证，不包含用户当前的私有配置。
