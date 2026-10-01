# 免费PDF桌面工具附件包

整理日期：2026-10-01。筛选标准：免费开源的桌面工具，不选试用版、不选付费企业版，不要求购买商业许可证。免费软件用于企业内部工作，与购买商业版是两回事；使用、修改和分发仍应遵守各工具的开源许可。

本包是选型与接入资料包，包含官方下载入口、许可来源、能力比较、示例和只读检测脚本；不内置第三方安装程序、不自动安装软件。这样可以从官方获取适合目标电脑的版本，并核验其签名及许可。版本以下载当天官方页面为准；本包未安装或验收这些替代工具。

## 三款可替代WPS办公功能的桌面程序

| 程序 | 免费版与许可 | 文档与PDF用途 | 接入SageWrite的区别 |
| --- | --- | --- | --- |
| LibreOffice Writer（自由办公文字处理器） | 免费开源；主体MPL 2.0，包含其他开源组件 | 编辑办公文档并导出PDF；官方有无界面批量转换参数 | 优先验证候选：05-build生成DOCX，再用soffice命令行导出；需新增并验收路线，不能直接冒充Word.Application |
| ONLYOFFICE Desktop Editors（桌面办公编辑器） | 免费开源桌面版；AGPL v3及官方附加说明 | 编辑DOCX等文档，桌面界面另存或打印成PDF | 适合人工检查与导出；本包没有证实其桌面版具有可直接替代05C的批量接口，不借用付费服务器版能力 |
| Apache OpenOffice Writer（开放办公文字处理器） | 免费开源；Apache 2.0及所含组件许可 | 编辑文档并导出PDF | 可作人工办公候选；复杂DOCX、目录、分页和字体须实测，不能假定与WPS一致 |

选择建议：自动化建设先验证LibreOffice；重视桌面DOCX编辑体验可比较ONLYOFFICE；OpenOffice列为另一免费办公候选。它们拥有相关办公和PDF能力，不代表完整覆盖WPS所有功能，也不保证这本书的49页排版完全一致。

官方下载及官方许可：

- LibreOffice：[下载](https://www.libreoffice.org/download/)、[许可](https://www.libreoffice.org/licenses/)、[命令行转换](https://help.libreoffice.org/latest/en-US/text/shared/guide/start_parameters.html)。查阅时下载页显示26.8.0，这是网页版本记录，未在本机安装验证。
- ONLYOFFICE：[免费桌面版](https://www.onlyoffice.com/desktop)、[许可与版本区别](https://www.onlyoffice.com/blog/2026/05/onlyoffice-license-and-trademark-policy)、[源码许可](https://github.com/ONLYOFFICE/desktop-apps/blob/master/LICENSE)、[桌面保存与打印](https://helpcenter.onlyoffice.com/docs/userguides/document_editor/SavePrintDownload.aspx)。只选Desktop Editors；不把付费Enterprise/Developer产品列入免费包。分发或修改时保留版权、品牌和源码义务，具体以官方许可为准。
- Apache OpenOffice：[下载](https://www.openoffice.org/download/)、[许可](https://www.openoffice.org/license.html)、[PDF导出指南](https://wiki.openoffice.org/wiki/Documentation/AOO4_User_Guides/Getting_Started/Printing%2C_Exporting%2C_and_E-mailing/Exporting_to_PDF)。

## 两款可以另建PDF路线的免费工具

| 工具 | 免费与许可 | 能力与边界 |
| --- | --- | --- |
| Chromium（开源浏览器） | 免费开源；主体BSD式许可和各第三方组件许可 | 可以预览PDF，也可把HTML网页打印成PDF；不负责直接将DOCX排版，须先构建HTML/CSS书籍模板 |
| Typst（开源排版工具） | 本地编译器免费开源，Apache 2.0；不依赖其付费在线服务 | 适合本地文稿排版与PDF生成；不是办公文档编辑器，需把书稿转换为Typst并建立中文、封面、目录及页眉页脚模板 |

官方来源：

- Chromium：[项目](https://www.chromium.org/chromium-projects/)、[获取构建](https://www.chromium.org/getting-involved/download-chromium/)、[许可](https://github.com/chromium/chromium/blob/main/LICENSE)、[无界面打印PDF参数](https://developer.chrome.com/docs/automation-and-testing/headless-cli)。官方原始构建更新与使用注意事项以下载页为准；Google Chrome属于不同发行产品，未装进本开源附件包。
- Typst：[源码与本地使用](https://github.com/typst/typst)、[编译器下载](https://github.com/typst/typst/releases)、[开源说明](https://typst.app/open-source/)。仅选本地开源编译器，不要求订阅云端套餐。

## 现有05C流程不变

当前正式路线仍是04F检查→05C→05-build/Pandoc→DOCX→Word.Application COM→PDF。本机通过验证的是WPS 12.1.0.28043服务。上述候选在本项目中尚未接入，也没有证实提供相同COM接口；下载软件不等于SageWrite已经支持它。替代路线采用独立输出目录，不覆盖已经验收的正式PDF。

`check-installed.ps1` 只检查指定路径或常见安装路径的文件版本，不启动第三方程序，不写书稿、不联网。它不能证明导出能力已通过验收。

```powershell
.\check-installed.ps1
.\check-installed.ps1 -LibreOfficePath 'C:\Program Files\LibreOffice\program\soffice.exe'
```

## 无Word/WPS的导出示例（尚未接入05C）

以下只说明官方工具的调用方式，用户需先从官方安装工具。示例路径应替换为实际绝对路径。不要直接覆盖正式输出，先用独立目录做验证。

```powershell
# LibreOffice：使用05-build已生成的DOCX作为输入。
& 'C:\Program Files\LibreOffice\program\soffice.com' `
  --headless --convert-to 'pdf:writer_pdf_Export' `
  --outdir 'D:\pdf-trial' 'D:\pdf-trial\manuscript.docx'

# Chromium：输入须为已经完成书籍排版的本地HTML，不是DOCX。
& 'C:\tools\chromium\chrome.exe' --headless `
  '--print-to-pdf=D:\pdf-trial\browser.pdf' `
  'file:///D:/pdf-trial/manuscript.html'

# Typst：输入须为已经完成模板转换的.typ文稿。
& 'C:\tools\typst\typst.exe' compile `
  'D:\pdf-trial\manuscript.typ' 'D:\pdf-trial\typst.pdf'
```

正式接入验收需记录软件版本、字体、源稿哈希、命令和新产物路径；检查封面不重复、全部章节和目录存在、中文可读、页眉页脚正确、表格与插图没有裁切、末页完整。版式不同不一定是错误，但必须按写作规范判断，不能仅以退出码或相同页数认定等价。

## 包内文件

- README.md：中文比较、许可来源、路线示例与验收要求。
- tools.json：可供程序读取的工具清单与官方入口。
- check-installed.ps1：不启动程序的本机文件版本检测。
- SHA256SUMS.txt：上述资料文件的校验值。

ZIP由仓库中的 `docs/attachments/build-free-pdf-tools.py` 可重复生成。附件包不含第三方程序代码或安装包，厂商名称仅用于识别工具；许可详情以链接对应的原始项目为准。
