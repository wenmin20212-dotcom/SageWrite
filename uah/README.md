# SageWrite 独立 UAH 安装包

SageWrite 提供建书、目录、正文、修订、审校、引用、封面与成书工具，由独立 UAH/BOSS 加载。它不包含 BOSS 宿主，不需要当前 Codex 会话帮助搬文件。

## 安装和启动

1. 从 SageWrite GitHub Release 下载 ZIP 和 SHA256，核对 ZIP 后解压到任意独立目录。
2. 双击 `启动安装.cmd`。可运行 `runtime/node.exe prepare.cjs "你的书籍目录"` 自定义书籍工作区。
3. 在 UAH 中选择本包目录，或执行 `BOSS.exe --uah-agent="本包绝对目录"`。首次加载后 UAH 创建本实例桌面快捷方式和独立聊天配置。
4. 在 UAH 中配置对话模型。用 PowerShell 运行本包 `Configure-Model.ps1`，按提示填写独立写作模型和密钥；或将 `模型配置.example.json` 复制为 `model.local.json` 后填写。两个配置目前独立，不会自动继承。
5. 对话说“新建一本书”。确认需求后由 SageWrite MCP 创建书籍，回执用于 UAH 登记项目。继续书籍时先查进度。

## 模型与依赖

文本生成默认使用你配置的 OpenAI-compatible 服务。凭据只写在本机 `model.local.json`，不要上传 GitHub。可主动配置 provider 为 `codex` 并安装、登录 Codex CLI；包不强制使用它。`codex_agent` 需要当前助手交接，不适合独立 UAH 运行，适配器会给出明确错误。

Windows x64；包包含 Node 运行时、MCP 依赖和 8 个 Skill。本机需 Windows PowerShell 5.1。写作需要有效模型服务；DOCX/EPUB/PDF、图片和出版操作还有各自依赖，详见 payload/SageWrite/docs 和引擎说明。工具存在不等于所有导出已验证。

书籍默认在本包 `books/workspace-书名/sagewrite/book`；聊天在 UAH 的实例数据目录。移动安装包后重新执行安装命令并重新选择包；旧聊天实例不会自动迁移。删除书籍前先备份。

## 构建

在独立 SageWrite 源码目录使用锁定的 pnpm 依赖：`pnpm --dir engine/mcp-server install --frozen-lockfile`，然后执行 `node uah/build.cjs 新输出目录 Windows-node.exe路径`。构建器拒绝覆盖已有输出、实体化依赖并转换 PowerShell UTF-8 BOM。Node 来源和版本由发布者记录；发布 ZIP 必须附 SHA256。

UAH 当前 v0.2 的 MCP args 不支持相对路径展开，所以安装脚本在本机生成路径化 agent.yaml。发布 BOM 记录解压原始文件；安装后 agent.yaml 与 installation.local.json 属于本机配置，不能把发布 BOM 当作安装后全目录不变的证明。
