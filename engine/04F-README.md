# 04F：成书前的格式审批

04F负责确定性格式检查，不调用AI，不代替内容审读。05正式DOCX、PDF、打印版和EPUB入口必须验证04F标记后才能构建。

## 日常流程

```powershell
# 第一次或修改书稿之后：备份并统一已有标题，再检查
.\04F.ps1 -BookName LTCAILearningEvolutionAcademic -Mode Normalize

# 仅检查，不改正文；通过也会签发新标记
.\04F.ps1 -BookName LTCAILearningEvolutionAcademic -Mode Check

# PDF和EPUB入口会自动验证标记，不会自动修改正文
.\05c-pdf.ps1 -BookName LTCAILearningEvolutionAcademic
.\05b-epub.ps1 -BookName LTCAILearningEvolutionAcademic
```

`04-edit.ps1 -NormalizeSubheadings`也委托04F处理，不再执行旧的编号修改路径。04-edit其他检查若出现错误，会撤销04F标记。旧的edit_report.json不能替代04F审批。

## 检查规则

- toc.md的小节、数值MD文件数量及顶层标题对应；正文小节不能重复或跳级。
- `####`标题统一为`4.2.1`、`4.2.2`等，更深层级相应延伸；处理中文序号、第一/第二、第一步/第一层、括号序号、已有错误编号和没有编号的明确标题。
- 代码围栏不修改；普通叙述和真正Markdown列表不自动转成标题。
- 疑似纯文字/粗体标题、缺空格标题等不猜测，应手动标为标题或明确列表后重跑。语义上缺了标题却没有明确标记的段落仍需人工审读；连续正文无子标题只提示，不一刀切补标题。
- 检查插图存在且位于当前书籍工作区，检查引用条目重复及缺失。
- 已采用04R的书籍先通过04R完整性检查，拒绝用格式处理掩盖未经审核的正文改动。纯标题规范化后保留备份和format_history，更新相应文件的散列并重跑04R。
- 当前TOC末尾尚未进入数值正文文件的“附录”规划单列提示，不把它们误当成已经交付的正文章节。若开始生成这些附录，应扩展目录编译与04R范围，而不是冒充已验证。

## 文件与失效机制

- 原文件备份：书籍`back/format_时间戳/`。
- 详细报告：`04_output/editorial_audits/format_preflight.json`，含逐行前后对照。
- 通过标记：`00_brief/format_preflight.json`。
- 标记绑定正文、目录、参考状态、书籍定义、封面、资源以及相关程序的SHA-256；增删文件或内容改变后验证失败。它不是“曾经运行过”的布尔值。
- 标记是本地完整性记录，不是防恶意篡改的密码学签名。不能手工修改标记来绕过检查。
- 05c和05cc不再在构建失败后退回旧DOCX导出PDF。未通过、标记缺失或过期时必须停止。

其他语言：`04F -Language en`按翻译工作区验证；也可显式传`-BookRoot`。程序不自动翻译或改写标题含义。

已锁定的`sagewrite-ps1-20260915`标签保持不动；本次格式与排版流程纳入`sagewrite-ps1-20260917`程序锁版，详见`RELEASE-20260917.md`。
