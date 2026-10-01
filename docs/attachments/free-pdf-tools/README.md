# 已实测的免费自动PDF辅助包

2026-10-01已在本机下载并运行后，才将以下两条自动路线纳入可用包。替换之前未实测的候选资料包；人工导出软件不属于可用附件。

| 路线 | 已下载并运行的版本 | 完整书稿实测结果 |
| --- | --- | --- |
| Typst（本地排版编译器） | 0.15.1，Windows x64官方包 | 37页；24单元标题、封面、三张插图齐全；41个目录链接；代表页面抽检通过 |
| Chromium（开源浏览器） | Windows x64官方快照1708478 | 40页；24单元标题、封面、三张插图齐全；41个目录链接；代表页面抽检通过 |

两条路线由脚本自动完成，没有人工另存PDF，没有启动WPS/Word。输入为同一份完整Markdown书稿及原始图片。Typst的自动目录带页码；Chromium提供点击跳转目录，不显示每章页码。不同引擎页数不同，均为独立辅助版式，不宣称与49页05C版式等价。

## 使用条件与步骤

Windows x64、Python 3.9及以上、Pandoc 3.11（本机实测）及本机中文字体。本机使用Microsoft YaHei（微软雅黑）；不分发字体。脚本只支持本次验证的结构：toc.md以二级标题为章、三级标题为单元，02_chapters包含数字命名的Markdown，每文件有一个三级单元标题；须有00_intake/cover.png。其他结构明确报错或须另行验证。

在交互桌面宿主的授权环境运行，沙箱若阻止程序执行，按宿主机制处理授权，不关闭安全限制来冒充成功。

```powershell
# 下载固定官方版本、核验SHA256并解压；不安装系统服务或改变Office。
python download-tools.py --engine typst --dest D:\SageWrite\engine\work\free-pdf-tools
python export.py --engine typst `
  --tool D:\SageWrite\engine\work\free-pdf-tools\runtime\typst\typst-x86_64-pc-windows-msvc\typst.exe `
  --pandoc C:\Users\1000\AppData\Local\Pandoc\pandoc.exe `
  --book-root D:\SageWrite\workspace-你的书名\sagewrite\book `
  --output-dir D:\SageWrite\engine\work\你的书名-typst
```

Chromium对应命令：

```powershell
python download-tools.py --engine chromium --dest D:\SageWrite\engine\work\free-pdf-tools
python export.py --engine chromium `
  --tool D:\SageWrite\engine\work\free-pdf-tools\runtime\chromium\chrome-win\chrome.exe `
  --pandoc C:\Users\1000\AppData\Local\Pandoc\pandoc.exe `
  --book-root D:\SageWrite\workspace-你的书名\sagewrite\book `
  --output-dir D:\SageWrite\engine\work\你的书名-chromium
```

替换实际绝对路径。输出目录要新建且独立，脚本拒绝覆盖同名PDF，生成auxiliary-typst.pdf或auxiliary-chromium.pdf和generation.json。字体可用--font指定，换字体后重新验收。每本书仍需检查中文、封面、目录、表格、插图与末页。

## 已剔除的候选

- LibreOffice 26.2.6.3：官方MSI已下载，签名有效且SHA256与官方一致，仅管理解包到隔离目录。05-build定制DOCX本次无法加载；原始Markdown经Pandoc重建的DOCX能自动转换，但目录为空。本次未通过，不发布可用导出脚本。
- ONLYOFFICE桌面版及Apache OpenOffice：此前只是人工导出候选，没有本项目可用自动路线，排除，不继续作为辅助程序发布。
- 首次Chromium/Typst通过DOCX中转丢图，已拒收。改成原始Markdown加复制图片并修复封面顺序后，对包内export.py重新进行完整书稿实测。

## 包内容与许可

export.py是实测自动入口；download-tools.py从官方地址下载固定版本、检查SHA256和解压路径；tools.json锁定版本；validation.json是脱敏验收记录；SHA256SUMS.txt校验包内文件。ZIP由上级build-free-pdf-tools.py重建。

工具已本地下载、解包并运行，原始包保存在忽略上传的engine/work目录。GitHub附件包含可运行脚本、固定下载地址与校验值，不重复上传数百MB第三方程序；下载脚本取得本次实测的同一原始发行包。这已不是只有清单的未验证资料包。

Typst本地编译器免费开源，Apache 2.0许可，不要求订阅在线服务：[源码与许可](https://github.com/typst/typst)、[固定发行包](https://github.com/typst/typst/releases/tag/v0.15.1)。官方ZIP自带LICENSE及NOTICE，解压保留。

Chromium免费开源，主体BSD式及第三方组件许可：[官方快照说明](https://www.chromium.org/getting-involved/download-chromium/)、[许可](https://github.com/chromium/chromium/blob/main/LICENSE)、[自动打印参数](https://developer.chrome.com/docs/automation-and-testing/headless-cli)。本附件不重分发Chromium二进制，不把它描述成Google Chrome发行产品。

正式05C保留不变；辅助包尚未注册成SageWrite MCP工具，先按脚本运行，不宣称旧MCP已支持这些引擎。
