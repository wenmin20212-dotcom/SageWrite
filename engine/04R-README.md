# 04R 按章参考文献整理

本程序将经过审核的引用计划应用到正文，并生成书末 `02_chapters/references.md`。前言和各章分别编组；不改变小节编号、标题或图片位置。

## 操作顺序

在 engine 目录执行。0 代表前言，1 代表第一章。

```powershell
.\04R.ps1 -BookName LTCAILearningEvolutionAcademic -Mode Plan -StartChapter 0 -EndChapter 1
```

Plan 只输出 JSON，不改正文。编辑需核实真实文献，填写 sources、groups 和各节 citations，明确需要删除的末尾提示段与必要的措辞修订，再将 reviewed 设为 true。verified 是审核记录，不代表程序自行完成了学术核验。每项来源须记录核验网址、日期、支撑内容与适用边界。

本次前言和第一章的审核计划已保存在书内，可直接执行：

```powershell
.\04R.ps1 -BookName LTCAILearningEvolutionAcademic -Mode Apply -PlanPath C:\Users\User\.openclaw\workspace-LTCAILearningEvolutionAcademic\sagewrite\book\00_brief\references\reviewed_frontmatter_ch01.json
.\04R.ps1 -BookName LTCAILearningEvolutionAcademic -Mode Check
```

Apply 先验证全部定位与原稿哈希，再备份到本书 back/references_时间戳，随后修改正文、生成参考文献及状态记录。相同计划重复执行不会重复修改。原稿后来改变，须重新生成并审核计划，不能忽略冲突强行执行。

## 编辑约束

- remove_blocks 只允许唯一匹配的文末文本；本版不删除小节标题。不能将最后一段自动视作参考文献说明。
- replacements 用 find、replace、reason 明确必要修改，保留原创边界和正文观点。
- citations 用 anchor、source_ids、support_note 明确观点与文献关系。正文保留简短标记，例如 [前-1]、[1-1]，完整条目只列在书末。
- 同一章相同来源只列一次，不同章可分别列出。sources 的 id 必须稳定。
- references.md 由程序维护，不手工修改；状态位于 00_brief/references/reference_state.json。
- 处理其他章时创建新的计划，沿用现有来源 ID；程序会保留已有分组并追加新章。
- 现有 05 构建流程会收录 references.md。执行 04R 不自动重出 PDF 或 EPUB。

## 本次范围

仅处理 01.md 至 09.md。后续章节文献尚未整理。当前条目包含作者、年份、题名、出版信息及来源链接；最终出版时仍需按出版社要求统一著录规范，并继续核查全书论断与出处的对应关系。
