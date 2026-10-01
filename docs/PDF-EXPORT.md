# PDF导出路径、版本与排错

免费自动替代路线见[已实测附件](attachments/free-pdf-tools/README.md)，[下载可运行ZIP](attachments/sagewrite-free-pdf-tools.zip)。Typst和Chromium已下载并用完整24单元书稿自动导出，附验收记录。它们采用独立辅助版式，未接入现有05C或注册为MCP工具；人工导出候选和本次验收失败的工具不在可用包内。

## 已成功的正式路径

MCP工具 `sagewrite_export_pdf`（PDF导出工具）调用 `engine/05c-pdf.ps1`。该脚本验证04F格式标记，调用同一引擎目录中的 `05-build.ps1`，由 Pandoc（文档格式转换工具）生成最新完整版DOCX，再由 `Word.Application` COM（桌面组件对象模型自动化接口）导出PDF。当前05C没有不依赖桌面COM服务的正式导出分支。

必须先确认这些实际路径，不能凭项目名称猜测：

| 路径 | 确认方法 |
| --- | --- |
| MCP入口 | 客户端配置中的 `src/index.mjs` 绝对路径，确认对应目标SageWrite版本 |
| PowerShell入口 | `SAGEWRITE_POWERSHELL` 或脚本使用的Windows PowerShell绝对路径 |
| 工作区父目录 | `SAGEWRITE_WORKSPACE_ROOT`；终端与MCP必须指向同一目标 |
| 书籍根目录 | `<工作区父目录>/workspace-<BookName>/sagewrite/book` |
| 中文源目录 | 书籍根目录；翻译版使用 `03_translation/<Language>` |
| 完整版DOCX | `04_output/<Language>/<BookName>_full.docx` |
| 正式PDF | `04_output/<Language>/<BookName>_full.pdf`；仅明确指定 `OutputPath` 时改变 |

从仓库根目录运行的示例，需替换书名与工作区：

```powershell
$env:SAGEWRITE_WORKSPACE_ROOT = 'D:\SageWrite'
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
  -NoProfile -ExecutionPolicy Bypass -File '.\engine\04F.ps1' `
  -BookName '<书名>' -Mode Check
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
  -NoProfile -ExecutionPolicy Bypass -File '.\engine\05c-pdf.ps1' `
  -BookName '<书名>' -Language zh
```

04F失败时先解决报告问题，再执行05C。05C会自行调用05-build，不应同时另开一个构建。脚本退出成功后，检查新文件的时间戳、章节、中文、目录、封面数量和插图；旧产物不能证明本次成功。

## 此前错误说明的纠正

2026-10-01，助手在沙箱内收到 `80040154`（组件类未注册）后，过早判断电脑没有Word、WPS或可用COM服务，随后另用PyMuPDF（PDF处理库）生成兼容版。这个判断没有先验证桌面宿主环境；替代生成器也不是05C正式流程。用户反馈乱码后，又生成过图像兼容版，它仍不能作为正式05C导出的证据。

后来对照同机《武当山传奇》的成功记录，使用相同的05C→05-build→COM渲染流程，在宿主授权的沙箱外环境成功导出。读取桌面注册表后确认，`Word.Application` 的实际服务是 WPS `wps.exe /Automation`。正式49页PDF包含24个写作单元、封面和三张插图，并完成代表页面的中文与版式检查。

正确排错顺序是：确认调用路径和工作区 → 核对04F与最新DOCX → 检查当前进程是否受沙箱限制 → 核对交互用户、32/64位注册表及COM服务路径 → 通过宿主授权机制重试同一05C命令。不能仅因受限进程看不到组件就断言软件未安装。MCP自身不能绕过宿主权限。

另已修复重复封面：05-build已嵌入源目录或02_chapters中的封面时，05C不再额外插入00_intake中的封面。两条入口共用同一正式流程。

## 桌面、客户端与COM的实测版本

以下是2026-10-01读取的本机版本，属于一次成功运行的基线，不是最低版本要求，也不是官网下载页承诺提供的固定版本。

| 组件 | 已核实版本或状态 | 官方获取与核查 |
| --- | --- | --- |
| Pandoc | 3.11；本机位置为用户目录下的 `AppData/Local/Pandoc/pandoc.exe` | [官方下载与安装](https://pandoc.org/installing.html)；运行 `pandoc --version` |
| WPS桌面客户端/COM服务程序 | 文件版本与产品版本均为12.1.0.28043 | [WPS官方客户端下载](https://365.wps.cn/download365)；安装后核查实际文件版本及完整05C导出 |
| Windows PowerShell客户端 | 5.1.19041.6456，实际调用 `System32/WindowsPowerShell/v1.0/powershell.exe` | Windows自带；使用 `$PSVersionTable.PSVersion` 核查 |
| SageWrite MCP服务 | `engine/mcp-server/package.json` 中版本1.0.0；Node.js要求20及以上 | [SageWrite仓库](https://github.com/wenmin20212-dotcom/SageWrite)；[Node.js官方入口](https://nodejs.org/en/download)；核对客户端配置的可执行路径 |
| MCP宿主客户端 | 本次没有核实具体产品版本；不能从MCP服务版本推断客户端版本 | 在实际宿主的“关于”页面记录版本；各宿主权限模式分别核实 |
| Microsoft Word | 本次成功导出没有核实或使用Microsoft Word的产品版本 | [微软官方下载与安装说明](https://support.microsoft.com/en-us/office/lifecycle/officeinstall/download-install-or-reinstall-microsoft-365-or-office-2024-on-a-pc-or-mac)；目标机按许可安装后另行验收 |
| COM接口 | ProgID为 `Word.Application`，CLSID为 `{000209FF-0000-0000-C000-000000000046}`；本机注册在32位视图，指向WPS自动化服务 | COM是客户端调用桌面服务的接口机制，不是另一个要单独下载的Word/WPS版本；见[微软COM客户端与服务说明](https://learn.microsoft.com/en-us/windows/win32/com/com-clients-and-servers) |

WPS服务的注册位置指向用户目录下的 `Kingsoft/WPS Office/<版本目录>/office6/wps.exe /Automation`。应读取目标机注册表的真实值，不硬编码本机短路径。不要用COM类标识当成软件版本号，也不要承诺官网当前安装包与本机版本一致。已验证的是该版本的阅读版导出，其他版本及印刷版须单独验收。

## 不使用Word或WPS的PDF能力边界

不需要人工打开Word/WPS界面操作，与完全不依赖其桌面程序，是两回事：现有05C自动运行COM服务，仍依赖该服务程序。

Pandoc本身可配合其他PDF引擎生成PDF，见[官方安装说明](https://pandoc.org/installing.html)。2026-10-01新增的附件export.py已实际跑通Markdown→Pandoc→Typst或Chromium→PDF，分别37页和40页，核查章节、中文、封面、三张插图和目录链接。它是独立自动辅助路线，不是05C的无Office正式分支；版式不同，每本书仍需验收。此前图像兼容版或PyMuPDF临时方案不能作为这两条新路线的测试证据。
