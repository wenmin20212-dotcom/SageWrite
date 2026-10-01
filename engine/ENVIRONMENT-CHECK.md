# 环境自检

`Test-SageWriteEnvironment.ps1`面向作者和安装Agent，检查当前电脑的静态前置条件。默认不改配置、不写书稿、不创建测试文件、不启动Word、Web、MCP或Codex，不访问网络、不调用模型、不安装软件。仅显式指定ReportDirectory时写入独立JSON报告。

```powershell
# 在engine目录执行
.\Test-SageWriteEnvironment.ps1
.\Test-SageWriteEnvironment.ps1 -Profile Writing
.\Test-SageWriteEnvironment.ps1 -Profile Pdf
.\Test-SageWriteEnvironment.ps1 -Profile Mcp -Json
.\Test-SageWriteEnvironment.ps1 -ReportDirectory .\work\environment-reports
```

Profile可选All、Core、Writing、Web、Pdf、Epub、Mcp、Images、SimpleDocx。每种选择均包含Core。WorkspaceRoot可显式指定工作区父目录，否则采用SAGEWRITE_WORKSPACE_ROOT或与00-common一致的默认父目录。

PDF 自检只反映当前进程可见的 `Word.Application` 注册信息。沙箱内可能报缺少注册，而桌面进程能够正常导出；应检查用户/会话、权限和32/64位注册表，并通过宿主授权机制重试原始05c流程。Microsoft Word是基准服务，本机WPS兼容服务通过过阅读版导出，但其他版本和印刷版须各自验收。不要因一次受限探测就要求安装Office，也不要用替代渲染器冒充05c导出成功。

## 结果含义

- pass：该项静态检查成立。例如命令在PATH上，不代表程序已经成功运行。
- fail：发现阻塞项，如缺少必需程序、模型配置不合法或MCP绝对路径不存在。
- warn：需要注意，如不同入口工作区不一致、HTTP传输或配置尚未建立。
- unverified：为保持只读而未验证，如目录写权限、Word激活、字体、模型额度或MCP握手。

每种功能有独立状态：blocked或requires_validation。本版不输出“完全可用”，不会将文件存在等同于完整安装验收。退出码0表示所选范围没有静态fail；1表示存在fail，不意味着其他功能不可用。All可能因可选MCP缺失返回1，写作或EPUB仍可单独检查。

## 覆盖与限制

- 模型检查复用00-llm的配置优先级，仅读取配置，不发送请求。API密钥只验证配置是否被适配器接受，不输出密钥、端点原值或底层异常。
- codex_agent需要当前活跃Agent处理交接请求；普通终端自检不能证明会话已接通。
- Web配置以安全PSD1数据导入读取，提示工作区不一致及无认证的外网监听；不证明密码有效。
- MCP检查包清单、命令及绝对参数路径，不安装依赖、不注册客户端。相对路径及客户端独立配置仍需人工核对。
- Word只检查COM注册，不验证启动、许可证或实际PDF输出。Python包导入、字体匹配和工作区写权限给出后续动作，不擅自进行探测。
- 可执行文件只做发现，不启动未知PATH程序或安装脚本。版本兼容、联网和端到端验收应在用户批准后另做。
- JSON报告包含检查状态和建议，不记录整份环境变量，也不记录凭据。报告默认唯一文件名，不覆盖旧报告。报告目录创建/写入失败属于执行错误。

自检与04F不同：本程序检查电脑环境，04F检查具体书稿与构建输入。自检不能代替04F，不会给05签发格式审批。
