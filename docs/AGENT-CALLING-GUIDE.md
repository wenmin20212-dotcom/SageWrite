# SageWrite Agent 调用手册

核对日期：2026-09-18。程序基线：`sagewrite-ps1-20260918`。本手册描述已检查的源码，不代表所有分支已在新电脑端到端验证。入口和参数变动后应同步更新文档。

## 1. 如何使用本手册

先读本手册的流程与输入输出约束，再查 [完整参数附录](AGENT-SCRIPT-PARAMETERS.md)，最后读取即将调用的脚本实现。附录收录 engine 顶层 Git 已跟踪的全部 87 个 PS1 的顶层参数声明；公共库及转发入口没有独立参数声明，不表示它们可以无参运行。

本文路径默认相对于书籍根目录 `$BookRoot`，脚本名默认相对于仓库 `engine`。正文流程覆盖全部顶层 00—09 编号脚本，另列安装、Web 服务和维护工具。`backup`、`bak0318`、历史 launchers 和测试文件不是生产入口。

**禁止从00到09逐个执行全部文件。** 编号中包含库、别名、替代方案、检查器和常驻服务。按任务选择路线，执行一步、检查产物，再进入下一步。

## 2. 环境、路径与状态

安装条件见 [README](../README.md)。Windows PowerShell 为运行基础；Web 需要 Node.js，正式 DOCX/EPUB 需要 Pandoc，当前 PDF 需要桌面 Word。简版 DOCX 需要 Python 与 python-docx；部分图像修补需要 ImageMagick；发布自动化需要 automation 的 npm 依赖、浏览器及用户账号。

脚本内的 API 调用与操作脚本的 Agent 会话是两回事。需要 `OPENAI_API_KEY` 和相应模型权限；不能只替换密钥接入另一家服务商。默认模型并不统一，应查附录。检查密钥只报告是否存在，不打印其内容。

从实际 engine 目录执行，示例书名不得替换成现有正式书进行测试：

```powershell
$BookName = 'AgentSmokeBook'
$env:SAGEWRITE_WORKSPACE_ROOT = Join-Path $HOME 'SageWriteWorkspaces'
$BookRoot = Join-Path $env:SAGEWRITE_WORKSPACE_ROOT "workspace-$BookName/sagewrite/book"
```

Web 的 `WorkspaceRoot` 与此环境变量应指向同一父目录。新进程需要继承相同配置；不要假设上一次终端设置仍有效。

| 文件或目录 | 含义与使用约束 |
| --- | --- |
| `00_brief/objective.md` | 书籍定义；写作前确认题目、对象、范围与风格 |
| `01_outline/toc.md` | 主目录与写作单元定义；不是聊天中临时提纲 |
| `01_outline/toc2.md` | 02b 扩展产物；03读取的是 toc.md，不能假定自动使用 toc2 |
| `02_chapters/NN.md` | 数字写作单元；文件序号不等同于书中章号 |
| `00_brief/rewrite_notes` | 03使用的补充修改要求；检查是否遗留旧任务要求 |
| `04_glossary/glossary.md` | 可选术语表；启用 ReferenceGlossary 前确认存在 |
| `02_chapters/references.md` | 04R维护的书末参考文献，不手动覆盖 |
| `00_brief/references/reference_state.json` | 引用状态、原稿完整性记录 |
| `03_assets`、封面及排版配置 | 成书资源；应在同一本书工作区内，不能引用他机临时文件 |
| `03_translation/<语言>` | 翻译书稿及清单，与源语言正文分开 |
| `04_output/<语言>` | 当前正式构建输出，中文通常为 zh |
| `07_cover` | 封面两套流程的材料与产物，见第7节 |
| `09_publish/<语言>` | 发布准备包、元数据、平台子目录与提交记录 |
| `logs`、`back`及各模块备份目录 | 日志与恢复材料；具体备份位置以运行清单为准，不假定全部在同一 back 下 |

### 2.1 编号与范围

调用03、04B33、04C44等之前，列出“文件序号 → 正文标题 → TOC写作单元”映射，并确认 StartChapter/EndChapter 范围。TOC 的 `###` 写作单元用于03分节；不要把书中“第八章”直接传成 `-Chapter 8`。

04R例外：`StartChapter/EndChapter` 是参考文献的书中章节分组，0表示前言。04Z1的 `SectionIndex` 是要删除的写作单元序号。各脚本不能共享一个未经解释的“章节号”。

### 2.2 修改与恢复

修改前确认用户授权范围，并备份受影响文件。`Force`、`ApplyRewrite`、`Normalize`、重新生成TOC、删除并重排单元都是写操作。`DryRun` 也可能写预览、日志或清单，并不通用于所有脚本。程序没有该参数时，不要擅自加上。

不要并发写同一本书。失败时检查实际文件与清单，不只看 PowerShell 退出码；部分脚本可能已完成前面几个单元。只重跑失败范围，不能默认从头覆盖。不要修改哈希或审批标记来消除报错。

## 3. 推荐任务路线

| 用户任务 | 路线与停止点 |
| --- | --- |
| 建新书 | 01 → 02 → 作者确认TOC；02b按需，不自动替换目录 |
| 写正文 | 确认写作单元映射 → 03小范围生成 → 检查字数、标题与内容 → 继续 |
| 接收外部审稿 | 04c2导入意见 → 核对计划；只有用户批准大修时才走04c3 |
| 大修重组 | 04c3预览 → PrepareOnly准备目录与备份 → 人工确认新目录 → 分批生成 |
| 小修或二审 | 04B33 → 审核JSON → 04C44同范围返修 → 04B33复审 |
| 字数或语言重复统计 | 04B34 / 04D；它们的报告不等于编辑审核通过 |
| 引用整理 | 04R Plan → Agent核验真实文献并完善计划 → Apply → Check |
| 正式导出 | 内容定稿、封面资源就位 → 04-edit → 04R检查（已采用时）→ 04F Check → 05路线 → 查看成品 |
| 翻译 | 03t → 03r按需 → 目标语言检查与04F → 05指定相同Language |
| 发布准备 | 已核验输出与封面 → 09-publish → 检查元数据和平台包 |
| 辅助上架 | 用户指定平台和范围 → 09f prepare → 检查结果 → 经授权进入平台支持的模式 |

封面通常需在最终04F检查和05导出之前就位，因此业务顺序并不是文件名前缀的数值顺序。06网页是任选入口，不属于必须执行的中间阶段。

## 4. 00—03：初始化、目录、写作与翻译

所有下表业务脚本都需要 `-BookName`。参数完整类型、默认值及必填标记见附录。

| 程序 | 关键参数 / 输入和前置条件 | 输出、风险与下一步 |
| --- | --- | --- |
| `00-common.ps1` | 公共函数库，由其他脚本点源加载 | 工作区上下文、日志和共用功能；不是初始化书籍的命令 |
| `00-layout.ps1` | 排版公共库 | 供构建读取排版规则，不独立生成书稿 |
| `01-intake.ps1` | 必填 Title、Audience、Type、CoreThesis、Scope、Style；可选Subtitle、Author | 创建工作区、objective.md、简介等；不要对已有书无备份重跑 |
| `02-structure.ps1` | objective.md、API配置；只有BookName参数 | 生成toc.md；会影响后续编号，先保存旧目录并审阅结果 |
| `02-structurebak.ps1` | 历史备份脚本 | 不作生产入口；旧路径实现不保证遵守工作区环境变量 |
| `02b-expand.ps1` | toc.md、objective.md；Chapter或All或范围；MinSubsections/MaxSubsections、Model | 输出toc2.md；需核对其与主目录关系，不直接覆盖定稿TOC |
| `03-write.ps1` | toc.md、objective.md、API；Chapter或范围；Model、MaxTokens、AdditionalInstructions、ReferenceGlossary | 写数字MD与运行记录；已有文件和Force语义先核对；字数以正文实际统计，token不等于中文字数 |
| `03t-translate.ps1` | 源语言正文、必填Language；Chapter/范围/All；Model、MaxOutputTokens | 目标语言brief/outline/chapters及translation_manifest.json；需检查完整性和术语 |
| `03r-refine.ps1` | 已有翻译、必填Language；Chapter/范围/All、Model | 修改翻译，保存refine_manifest.json及_refine_backups；不是源稿精修入口 |

新书最小调用示例（02、03会调用API并可能计费，不是无副作用测试）：

```powershell
.\01-intake.ps1 -BookName $BookName -Title '测试书' -Audience '成人读者' -Type '指南' -CoreThesis '测试工作流' -Scope '一个小主题' -Style '清晰简洁'
.\02-structure.ps1 -BookName $BookName
# 先审阅实际生成的TOC并确认第1个写作单元。
.\03-write.ps1 -BookName $BookName -Chapter 1 -Model 'gpt-5.5'
```

## 5. 04：审稿、返修、参考文献与格式

| 程序 | 输入与调用条件 | 输出与注意事项 |
| --- | --- | --- |
| `04-edit.ps1` | BookName；Strict可选；NormalizeSubheadings是写操作 | logs/edit_report.txt、json及历史报告；格式规范化委托04F；不是大模型内容审稿 |
| `04b-epub.ps1` | 已有EPUB，BookName | logs/epub_report.*；当前读取旧式04_output根目录的BookName_full.epub，与05b语言子目录可能不一致；先核对目标，不能把旧EPUB检查当作新版验收 |
| `04b33-editorial-action-review.ps1` | 正文、TOC；Chapter/范围、ScopeName；可指定ExternalBriefPath、PreviousReviewPath、输出路径、BatchSize、Model；支持DryRun | 默认00_brief/<ScopeName>_revision_actions.json和编辑报告，logs/editorial_loop中批次与快照；生成意见而非直接完成返修 |
| `04B33.ps1` | 转发上一脚本的全部参数 | 短入口，与长入口二选一，不重复运行 |
| `04b34-part-budget-statistics.ps1` | TOC、正文；StartChapter/EndChapter、预算上下限、ScopeName | 00_brief中预算统计JSON/MD；报告实际统计口径，不将中文字符数当成token |
| `04B34.ps1` | 转发04b34参数 | 同上 |
| `04c-editorial-loop.ps1` | objective、TOC、正文及可选外部意见；Round选择Constitution/Developmental/Consistency/Reader/LineEdit/FullDiagnostic | logs/editorial_loop下意见、计划等；ApplyRewrite才进入相应执行；DryRun预览不代表AI审阅完成 |
| `04c2-third-party-audit.ps1` | 必填AuditPath、BookName；可指定SourceName、EditorialRunPath、范围 | 导入第三方意见并整合报告/返修计划；NoEditorialLoopReports、NoExportRevisionPlan改变输出；ApplyRewrite不是普通导入，需授权 |
| `04c3-accepted-audit-rewrite.ps1` | 已接受的审稿计划；RevisionPlanPath、ExternalBriefPath、MasterReportPath可显式指定；范围和模型 | 备份、重组TOC、生成改稿及manifest；PrepareOnly仍可能调用模型改TOC；SkipTocPreparation仅用于已核对目录；不是小修默认入口 |
| `04c44-revision-executor.ps1` | 已核对的PlanPath，或ScopeName对应意见JSON；Chapter/范围、Model、DryRun | 更新正文，记录revised_snapshots、manifest和00_brief/<scope>_04c44_latest_execution.json；执行前确认计划针对当前稿件 |
| `04C44.ps1` | 转发04c44参数 | 同上 |
| `04d-repeat-audit.ps1` | 正文范围、MinSentenceLength、DuplicateThreshold、StockPatterns、ReportName | 04_output/editorial_audits下重复表达报告；不能自动裁定重复在语义上必须删除 |
| `04D.ps1` | 转发04d参数 | 同上 |
| `04f-format-common.ps1` | 公共库 | 04F及构建用；不要直接当检查命令执行 |
| `04F.ps1` | BookName、Mode=Check/Normalize/Verify；可选BookRoot、Language | 报告与00_brief/format_preflight.json；Check检查并可签发标记，Normalize备份后改格式，Verify验证已有标记；必须处理失败原因 |
| `04R.ps1` | BookName、Mode=Plan/Apply/Check；章节分组范围或PlanPath、可选BookRoot | 引用计划、正文标记、references.md和reference_state.json；Plan不自动查证文献；Apply前计划必须真实核验 |
| `04z1-remove-section-renumber.ps1` | 必填SectionIndex、BookName；ExpectedHeading、EndIndex、ScopeName、DryRun | 删除单元并调整后续序号、目录，生成备份与报告；必须先DryRun，核查图片和跨章引用，不假定所有语义引用能自动修正 |
| `04Z1.ps1` | 转发04z1参数 | 同上 |

小范围审稿示例（范围为写作单元序号）：

```powershell
.\04B33.ps1 -BookName $BookName -StartChapter 1 -EndChapter 5 -ScopeName 'sample' -DryRun
# 核对预览后，去掉DryRun执行真实审稿。
.\04B33.ps1 -BookName $BookName -StartChapter 1 -EndChapter 5 -ScopeName 'sample'
$Plan = Join-Path $BookRoot '00_brief/sample_revision_actions.json'
# 先审阅JSON，确认任务与当前正文匹配。
.\04C44.ps1 -BookName $BookName -PlanPath $Plan -ScopeName 'sample' -StartChapter 1 -EndChapter 5 -DryRun
# 用户确认后再去掉DryRun执行返修；返修完成应复审，不自动宣称通过。
```

引用计划字段和审核要求见 [04R说明](../engine/04R-README.md)；其中旧书名、绝对路径和“本次范围”是历史示例，不是所有书的默认范围。格式标记与失效规则见 [04F说明](../engine/04F-README.md)。

## 6. 05—06：导出与网页入口

05下列构建入口均接受BookName、Language（默认zh）、AutoNumber。不要为解决标题不一致直接盲加AutoNumber，应先确定TOC和排版规则。非中文构建应有对应翻译工作区。

| 程序 | 前置条件 / 输入 | 输出与验收 |
| --- | --- | --- |
| `05-build.ps1` | 已通过04F的书稿、资源、排版配置；Pandoc | 04_output/<语言>/BookName_full.docx等构建产物；检查封面、章节分页、目录、引用 |
| `05a-simple-docx.ps1` | 正文、Python、python-docx；调用05a-simple-docx.py | 简版DOCX替代路线；不把它当正式05的检查或排版等价物 |
| `05aa-simple-docx-toc.ps1` | 同上 | 含目录的简版路线；实际文件名以输出日志为准，防止覆盖其他路线产物 |
| `05b-epub.ps1` | 有效04F标记、Pandoc、资源 | BookName_full.epub；检查目录、图片、封面及内部引用，不只检查ZIP可解压 |
| `05c-pdf.ps1` | 有效04F标记、Pandoc及桌面Word | 调05-build后导出BookName_full.pdf；失败不得用旧DOCX冒充新输出 |
| `05ca-print-docx.ps1` | 有效04F标记、Pandoc、印刷排版要求 | BookName_print.docx；检查开本与章节起页 |
| `05cc-print-pdf.ps1` | 有效04F标记、Pandoc、Word | 调05ca后生成BookName_print.pdf；需实际查看印刷版页面 |
| `06-web.ps1` | Node.js和本地配置；Port、HostName、WorkspaceRoot等见附录 | 转入Web启动逻辑，常驻服务，不生成一本书；API密钥仍需单独配置 |

```powershell
.\04-edit.ps1 -BookName $BookName
# 采用04R的书还须运行04R Check并处理失败。
.\04F.ps1 -BookName $BookName -Mode Check
# 只有确认检查通过，才分别执行所需的导出。
.\05c-pdf.ps1 -BookName $BookName -Language zh
.\05b-epub.ps1 -BookName $BookName -Language zh
```

Agent应分步运行并检查每步结果，上面代码不是忽略中间失败的批处理模板。不要同时运行多个同书构建进程。

## 7. 07—08：封面与图像

### 7.1 通用条件与两条路线

`07a-cover-assist.ps1` 必填BookName和Request，可选Title/Subtitle/Author、Edition和Model；根据自然语言要求提供封面辅助处理。调用前检查其处理的任务和输出，不把它理解成必然生成最终位图的统一入口。

旧路线根目录为 `07_cover/<Edition>`，新08n路线为 `07_cover/next/<Edition>`。Edition通常为ebook或print。两条路线输入清单不同，不能随意拼接。公共08n-common还定义兼容目录；最终构建是否选择新封面，必须检查导出清单及05实际资源解析，不能仅凭图片已存在。

大多数封面步骤依赖Windows System.Drawing和字体。默认印刷页数264、书脊0.595英寸等是程序默认值，不是当前书的真实规格。应根据最终页数、纸张与平台要求填写Print参数。

### 7.2 旧封面路线

下表均需BookName；Edition、Mode、Force等是否支持请查参数附录。Force可能清理或重做已有成果。

| 程序 | 输入 / 主要参数 | 输出与前置关系 |
| --- | --- | --- |
| `08-cover.ps1` | 书籍定义；Title/Subtitle/Author、Variants、Mode、SkipLayout/SkipMockup、Print参数 | 组合调度旧封面流程；只选需要的路线，不与下列子步骤无差别重复运行 |
| `08a-brief.ps1` | objective及可选标题信息 | brief/cover_brief.json等封面简报 |
| `08b-strategy.ps1` | cover_brief.json、Mode | brief/cover_strategy.json与方案 |
| `08c-generate.ps1` | strategy、Variants、Mode | drafts中候选图及generation_manifest.json；为local-placeholder草图，不等同于图像模型成稿 |
| `08d-review.ps1` | 候选图和generation_manifest | reviews/cover_review.json；程序评分不代替人工审美和出版审核 |
| `08e-layout.ps1` | 简报、审核后候选图、标题信息 | layout及layout_manifest.json；确认中文字体及文字完整性 |
| `08f-mockup.ps1` | layout_manifest | mockup及mockup_manifest.json；展示图不是印刷封面文件 |
| `08g-copy.ps1` | 简报、API配置 | brief/cover_copy.json等文案；作者简介等占位内容需核实 |
| `08h-frontmatter.ps1` | 简报、文案及标题信息 | 00_frontmatter/<Edition>的cover_page.md、title_page.md、copyright_page.md和manifest；核查真实版权信息 |
| `08z-export.ps1` | 布局/评审等清单，SkipLayout/SkipMockup及Print参数 | final/cover_export_manifest.json与封面导出；回退草图路径不代表质量达标 |
| `08-cover-drafts.ps1` | BookName、Edition、标题、Variants、Mode | 分阶段草图包装入口；先读其子程序调用，不与08-cover重复覆盖 |
| `08-cover-layout.ps1` | BookName、Edition、标题、Mode；已有前段产物 | 分阶段排版包装入口 |
| `08-cover-mockup.ps1` | BookName、Edition、Mode；已有布局 | 分阶段展示图包装入口 |

### 7.3 08n无字底图路线

| 程序 | 输入 / 主要参数 | 输出与限制 |
| --- | --- | --- |
| `08n-common.ps1` | 共享路径与读写库 | 供子脚本点源，不直接运行 |
| `08n-cover.ps1` | BookName、Edition、标题、Variants、Mode、SkipMockup/SkipPrintSpread、Print参数 | 总调度：brief→prompt→generate→review→layout→spread/mockup→export；其中generate仍是占位图 |
| `08n-base-brief.ps1` | objective、toc和标题 | base/base_brief.json、md |
| `08n-base-prompt.ps1` | base_brief.json | prompts/base_prompts.json、md；生成提示材料不等于图像生成 |
| `08n-base-generate.ps1` | base_prompts.json、Variants、Mode | imports中的占位PNG及base_generation_manifest.json；要正式图需另行生成/导入，不能把成功退出当完成成稿 |
| `08n-base-review.ps1` | imports内图片及可用清单 | reviews/base_review.json、md；替换图片后重做审核与后续布局 |
| `08n-title-layout.ps1` | base_brief、base_review与标题 | layout/title_layout_manifest.json及布局图 |
| `08n-midjourney-prompt.ps1` | chief.md或objective.md、TOC、API、Model | prompts/midjourney_prompt.txt及报告；不直接调用Midjourney生成图像 |
| `08n-image-edit.ps1` | InputFile或已导入底图、书名、API图像权限；ImageModel、CoverText等 | layout中的编辑图、ai_image_edit_report及workbench_state；调用images/edits，需检查文字准确性及与后续导出的衔接 |
| `08n-print-spread.ps1` | title_layout_manifest、真实Print规格；Edition默认print | print_spread_manifest及展开图；页数、出血、书脊不能盲用默认值 |
| `08n-mockup.ps1` | title_layout_manifest | mockup/mockup_manifest.json及展示图 |
| `08n-export.ps1` | brief、prompt、review、layout及可用其他清单 | final/next_cover_export_manifest.json、next_cover_report.md等；检查最终图是否确为选定版本 |

正式封面建议在底图导入处设人工确认点。若08n总调度已生成占位图，不要继续把它用于出版；更换为确认后的底图，再运行依赖它的步骤。封面变化后重新执行04F与05。

## 8. 09：发布准备与平台操作

发布准备与真实发布是不同阶段。不得未经用户授权上传、修改线上书目、设置价格或点击最终发布。账号登录、验证码和权利/税务/收款信息应由用户处理；程序的prepare成功不代表平台接受作品。

| 程序 | 输入 / 参数 | 输出与前置条件 |
| --- | --- | --- |
| `09-publish.ps1` | BookName、Language、Platform=all/amazon/apple/google、Force | 调09a/09b和所选平台打包器；需要已有构建、封面和书籍信息；本地打包不是上架 |
| `09a-collect.ps1` | 当前语言输出、封面和brief | 09_publish/<语言>/publish_assets.json；核对收集的是最新文件，不是旧版本 |
| `09b-metadata.ps1` | publish_assets.json与书籍信息 | publish_metadata.json、md；先审阅标题、作者、简介、语言等 |
| `09c-amazon.ps1` | 公共metadata和资源 | amazon/metadata.json、amazon_kdp_package.json、简介/关键词/检查单/封面；定价、地区、DRM等仍需确认 |
| `09d-apple.ps1` | 公共metadata和资源 | apple/metadata.json、apple_books_package.json等；非Apple平台自动批准 |
| `09e-google.ps1` | 公共metadata和资源 | google/metadata.json、google_play_books_package.json等 |
| `09f-submit.ps1` | BookName、Language、Platform、Mode；可选AttachChrome、ChromeDebugPort、ReuseSession、Force | submit_runs/<时间>/submit_request.json、submit_result.json及平台结果；可自动准备本地包，需读各平台结果 |
| `09g-amazon-bot.ps1` | 必填RunRoot、BookName；已有amazon metadata、Node/automation；Mode=prepare/draft/assist/details/content | RunRoot/amazon_result.json；直接调用时自行提供独立RunRoot，通常优先09f |
| `09h-google-bot.ps1` | 必填RunRoot、BookName；google包、Node/automation；Mode=prepare/draft/assist | RunRoot/google_result.json；不要把amazon的details/content传给它 |
| `09i-apple-delivery.ps1` | 必填RunRoot、BookName；apple包、Node/automation；Mode=prepare/draft/assist | RunRoot/apple_result.json；不支持AttachChrome参数，不从其他平台照抄 |

09f虽然接受details/content，但不是所有子平台都接受，使用这些模式时应限定amazon并核对调度实现。浏览器自动化依赖网站界面，界面变化可能使既有脚本失效；不能以自动化结束代替检查门户状态。

```powershell
.\09-publish.ps1 -BookName $BookName -Language zh -Platform amazon
# 人工或Agent审阅准备包后，仅进行准备检查。
.\09f-submit.ps1 -BookName $BookName -Language zh -Platform amazon -Mode prepare
```

## 9. 安装、服务与其他顶层脚本

完整参数仍见附录。此表补足编号流程以外的生产辅助入口。

| 程序 | 用途 / 条件 / 输出 |
| --- | --- |
| `Install-SageWrite-Standalone.ps1` | 配置本地/云入口、工作区，按需注册任务；DryRun会打印拟写配置，不传真实密钥做可记录预览；不安装外部依赖 |
| `Start-SageWrite-Web.ps1` | 读取配置并启动Node服务；确认端口和工作区；常驻进程不是卡死 |
| `Run-SageWrite-WebTask.ps1` | 计划任务启动包装；先读配置与日志路径，不当普通一次性生成脚本 |
| `Install-SageWrite-WebTask.ps1` | 注册自启动；权限与AtLogon/AtStartup选择须明确，不默认SYSTEM |
| `Get-SageWrite-WebTask.ps1` | 查看任务状态；存在任务不等于Web健康 |
| `Uninstall-SageWrite-WebTask.ps1` | 移除计划任务；仅在用户要求停止该自动启动时执行 |
| `New-SageWrite-StandalonePackage.ps1` | 需要Git；Ref指定版本、OutputRoot和VersionName；输出源码ZIP，不打包Word/API密钥/书稿 |
| `kdp-acceptance-files.ps1` | KDP验收材料辅助，按其文件参数和实际平台需求使用；不代替平台审核 |
| `kdp-composite-image-region.ps1` | 图像区域合成；依赖ImageMagick，明确输入、区域和输出，保留原图 |
| `kdp-crop-image-region.ps1` | 图像区域裁切；核对坐标与尺寸，不盲用其他封面坐标 |
| `kdp-fill-image-region.ps1` | 图像区域填充；检查填充效果和是否遮挡文字 |
| `kdp-resize-image-region.ps1` | 图像区域尺寸处理；核对比例及输出尺寸 |
| `kdp-imagemagick-fix.ps1` | 按结构化指令进行ImageMagick修补；先读指令格式、验证输入与输出报告 |
| `kdp-fix-image-edit.ps1` | 图像编辑修补入口；先核对所用服务、参数及费用，再执行，不能当纯本地无副作用工具 |
| `kdp-png-to-pdf.ps1` | PNG转PDF；核对印刷尺寸、DPI和输出，不代替正文PDF构建 |
| `clean.ps1` | 清理工具，可能删除文件；必须先读完整实现并核对删除路径，不纳入自动初始化 |
| `test-broken.ps1` | 测试用途，不纳入生产调用；不要求其作为安装成功条件 |

## 10. 每次交付的检查清单

1. 说明程序版本、书名、工作区、文件范围与所选路线。
2. 记录调用参数但遮蔽凭据，保留日志、返回状态与错误信息。
3. 核对实际产物存在、更新时间和内容；已有文件被跳过时明确报告“复用”，不能说新生成。
4. 对改稿报告字数统计口径、备份位置、审稿意见执行情况和未完成项。
5. 对构建报告04F及引用检查状态，查看实际封面、分页、目录、插图和引用链接。
6. 对发布分别报告本地准备、浏览器操作、上传、平台审核等状态，不能合并成笼统“已发布”。

本手册解决调用导航，不承诺跨设备无人值守运行。遇到输入缺失、权限不足、模型不支持、占位图或平台登录阻塞，应停止对应步骤并报告具体条件，而不是绕过检查继续执行。
