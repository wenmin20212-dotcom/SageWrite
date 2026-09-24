param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Model = "",

    [int]$Chapter,

    [int]$StartChapter,

    [int]$EndChapter,

    [int]$BatchSize = 5,

    [int]$MaxTokens = 9000,

    [int]$MaxSectionChars = 8500,

    [string]$OutputJsonPath,

    [string]$OutputReportPath,

    [string]$ExternalBriefPath,

    [string]$PreviousReviewPath,

    [string]$ScopeName = "learn_part",

    [switch]$DryRun
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath
$LlmPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-llm.ps1"
. $LlmPath

function Save-Utf8File {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $Parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($Parent) -and !(Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true))
}

function Read-Utf8File {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Resolve-OptionalExistingPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Path not found: $Path"
    }

    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Limit-Text {
    param(
        [string]$Text,
        [int]$MaxChars
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    if ($Text.Length -le $MaxChars) {
        return $Text
    }

    return $Text.Substring(0, $MaxChars) + "`r`n`r`n[04B33 truncated this section for review prompt length; judge from the supplied part plus metrics.]"
}

function Normalize-AiJsonOutput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Clean = $Content.Trim()
    if ($Clean -match '^(?:```json|```)\s*\r?\n([\s\S]*?)\r?\n```$') {
        $Clean = $Matches[1].Trim()
    }

    $Start = $Clean.IndexOf("{")
    $End = $Clean.LastIndexOf("}")
    if ($Start -lt 0 -or $End -lt $Start) {
        throw "AI output did not contain a JSON object."
    }

    return $Clean.Substring($Start, $End - $Start + 1)
}

function Normalize-MarkdownOutput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Normalized = $Content.Trim()
    if ($Normalized -match '^(?:```markdown|```md|```)\s*\r?\n([\s\S]*?)\r?\n```$') {
        return $Matches[1].Trim()
    }

    return $Normalized
}

function Normalize-ComparableTitle {
    param([string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return ""
    }

    $Clean = $Title.Trim()
    $Clean = $Clean -replace '^[#\s]+', ''
    $Clean = $Clean -replace '["''“”‘’：:，,。.\s\-—_]+', ''
    return $Clean.ToLowerInvariant()
}

function Invoke-SageTextGeneration {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,

        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$ModelName,

        [Parameter(Mandatory=$true)]
        [int]$OutputTokenLimit
    )

    $CallConfig = Copy-SageLlmConfig -Config (Get-SageLlmConfig) -ModelOverride $ModelName
    $OutputText = Invoke-SageLlmText -Prompt $Prompt -Config $CallConfig -MaxOutputTokens $OutputTokenLimit

    if ([string]::IsNullOrWhiteSpace($OutputText)) {
        throw "AI response was empty."
    }

    $InputTokens = 0
    $OutputTokens = 0
    $TotalTokens = 0

    return @{
        content = (Normalize-MarkdownOutput -Content $OutputText)
        usage = @{
            input_tokens = $InputTokens
            output_tokens = $OutputTokens
            total_tokens = $TotalTokens
        }
    }
}

function Get-FrontMatterValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [string]$Key
    )

    $Normalized = $Content -replace "`r", ""
    if (-not $Normalized.StartsWith("---`n")) {
        return ""
    }

    $Match = [regex]::Match($Normalized, "(?s)^---\n(.*?)\n---")
    if (-not $Match.Success) {
        return ""
    }

    foreach ($Line in ($Match.Groups[1].Value -split "`n")) {
        if ($Line -match "^\s*$([regex]::Escape($Key))\s*:\s*(.+?)\s*$") {
            return $Matches[1].Trim().Trim('"')
        }
    }

    return ""
}

function Get-ScopedTocSections {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TocContent,

        [Parameter(Mandatory=$true)]
        [string]$ChapterRoot,

        [int]$Chapter,

        [int]$StartChapter,

        [int]$EndChapter
    )

    $Matches = [regex]::Matches($TocContent, "^###\s+(.+)", "Multiline")
    $Total = $Matches.Count
    if ($Total -eq 0) {
        throw "No ### writing sections detected in toc.md."
    }

    if ($Chapter -and ($StartChapter -or $EndChapter)) {
        throw "Cannot use -Chapter together with -StartChapter/-EndChapter."
    }

    if ($Chapter) {
        if ($Chapter -lt 1 -or $Chapter -gt $Total) {
            throw "Chapter index $Chapter is outside available writing section count $Total."
        }
        $Start = $Chapter
        $End = $Chapter
    }
    elseif ($StartChapter -or $EndChapter) {
        if (-not $StartChapter -or -not $EndChapter) {
            throw "Both -StartChapter and -EndChapter must be specified."
        }
        if ($StartChapter -lt 1 -or $EndChapter -gt $Total -or $StartChapter -gt $EndChapter) {
            throw "Invalid chapter range $StartChapter-$EndChapter for available writing section count $Total."
        }
        $Start = $StartChapter
        $End = $EndChapter
    }
    else {
        $Start = 1
        $End = $Total
    }

    $Sections = @()
    for ($i = $Start; $i -le $End; $i++) {
        $FileName = "{0:D2}.md" -f $i
        $Sections += [pscustomobject]@{
            Index = $i
            Total = $Total
            TocTitle = $Matches[$i - 1].Groups[1].Value.Trim()
            FileName = $FileName
            Path = Join-Path $ChapterRoot $FileName
        }
    }

    return $Sections
}

function Count-Pattern {
    param(
        [string]$Text,
        [string]$Pattern
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return 0
    }

    return ([regex]::Matches($Text, $Pattern)).Count
}

function Get-SectionMetrics {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    $RiskPhraseCount = 0
    foreach ($Phrase in @("不是", "而是", "并非", "不能", "需要强调", "需要注意", "由此看", "从这个意义上说", "学术支撑", "可以概括为")) {
        $RiskPhraseCount += Count-Pattern -Text $Content -Pattern ([regex]::Escape($Phrase))
    }

    return [ordered]@{
        cjk_chars = Count-Pattern -Text $Content -Pattern "[\u4e00-\u9fff]"
        headings = Count-Pattern -Text $Content -Pattern "(?m)^#{3,4}\s+"
        nul_count = ($Bytes | Where-Object { $_ -eq 0 }).Count
        risk_phrase_count = $RiskPhraseCount
        not_count = Count-Pattern -Text $Content -Pattern "不是"
        not_but_count = Count-Pattern -Text $Content -Pattern "而是"
        academic_support_count = Count-Pattern -Text $Content -Pattern "学术支撑"
        mcar_count = Count-Pattern -Text $Content -Pattern "MCAR"
        goal_count = Count-Pattern -Text $Content -Pattern "GOAL"
        ltc_count = Count-Pattern -Text $Content -Pattern "LTC"
        learn_count = Count-Pattern -Text $Content -Pattern "Learn"
        tech_count = Count-Pattern -Text $Content -Pattern "Tech"
        create_count = Count-Pattern -Text $Content -Pattern "Create"
        ai_count = Count-Pattern -Text $Content -Pattern "AI"
    }
}

function New-ReviewPrompt {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookName,

        [Parameter(Mandatory=$true)]
        [array]$SectionRecords,

        [string]$ExternalBriefContent,

        [string]$PreviousReviewContent,

        [string]$ScopeName
    )

    $BriefBlock = if (-not [string]::IsNullOrWhiteSpace($ExternalBriefContent)) {
@"

【第三方责任编辑审计简报】
$ExternalBriefContent
"@
    } else {
        ""
    }

    $PreviousReviewBlock = if (-not [string]::IsNullOrWhiteSpace($PreviousReviewContent)) {
@"

【上一轮阶段性审读意见】
$PreviousReviewContent
"@
    } else {
        ""
    }

    $SectionsBlock = ""
    foreach ($Record in $SectionRecords) {
        $MetricsJson = $Record.metrics | ConvertTo-Json -Depth 8 -Compress
        $SectionsBlock += @"

===== SECTION_BEGIN =====
chapter_index: $($Record.chapter_index)
file: $($Record.file)
toc_title: $($Record.toc_title)
frontmatter_title: $($Record.title)
title_matches_toc: $($Record.title_matches_toc)
metrics_json: $MetricsJson
content:
$($Record.content)
===== SECTION_END =====
"@
    }

    return @"
你是 SageWrite 工作流中的 04B33：出版责任编辑审读 AI。

你的任务：只审读，不改正文。你要对每一个输入的小节提出可执行的编辑修改意见，并把结果输出为严格 JSON。后续 04C44 会读取你的 JSON，逐小节执行修稿。

书名：$BookName
审读范围标识：$ScopeName

总体编辑原则：
1. 不要推翻已经成立的 LTC / Learn / MCAR / GOAL 结构，除非某节确实出现结构性错误。
2. 区分不同处理动作：有些小节通过，有些小修，有些压缩，有些只重写开头，有些需要中度改写。不要把所有小节都判成同一种动作。
3. 优先发现出版层面的真实问题：开头吸引力、模板化句式、重复铺垫、概念混淆、术语不统一、学术支撑段过于内部说明化、模型堆砌、字数偏长或偏短。
4. 如果 toc_title 与 frontmatter_title 不一致，或正文主标题明显不属于当前 toc_title，优先判定为 P0 + rewrite_section；不要把旧稿当作当前小节进行小修。
5. 审稿意见要能被程序执行：每节都要给出 primary_action、priority、具体修改要求、保留内容、禁止改动、验收标准。
6. 如果一节已经合格，请使用 no_change，不要为了显得有工作量而强行修改。
7. 如果只需要改开头，请使用 rewrite_opening，并说明只改前几段，正文主体不动。
8. 如果需要压缩，请使用 compress，并给出目标压缩比例。
9. 如果学术支撑段需要调整，但正文主体可以保留，请在 secondary_actions 中加入 academic_style_fix。
10. 不要要求虚构文献；学术依据只能要求“核验、补充、集中到参考文献或脚注体例”。
11. 所有意见必须用中文写。

允许的 primary_action 只能从以下枚举选择：
no_change
light_polish
medium_polish
compress
rewrite_opening
rewrite_section
academic_style_fix
terminology_fix
mixed_revision

允许的 secondary_actions 只能从以下枚举选择，可为空数组：
light_polish
medium_polish
compress
rewrite_opening
rewrite_section
academic_style_fix
terminology_fix
model_consistency_fix
citation_fix
structure_fix
title_fix

priority 只能从以下枚举选择：
P0
P1
P2
P3

请严格输出一个 JSON 对象，不要 Markdown，不要代码围栏，不要解释。

JSON schema：
{
  "batch_summary": "本批次总体判断，100字以内",
  "items": [
    {
      "chapter_index": 5,
      "file": "05.md",
      "title": "1.1 从AI进入日常学习开始",
      "primary_action": "rewrite_opening",
      "secondary_actions": ["light_polish", "academic_style_fix"],
      "priority": "P1",
      "editorial_verdict": "一句话总判断",
      "problems": ["具体问题1", "具体问题2"],
      "revision_instructions": ["04C44应执行的具体修改要求1", "具体修改要求2"],
      "target_cjk_min": 1600,
      "target_cjk_max": 2100,
      "compression_target_percent": 0,
      "preserve": ["必须保留的观点、模型、案例或衔接"],
      "do_not_change": ["不能改动的结构或边界"],
      "acceptance_criteria": ["修后验收标准1", "修后验收标准2"],
      "notes_for_04c44": "给修稿程序的简短执行说明"
    }
  ]
}

$BriefBlock

$PreviousReviewBlock

【待审读小节】
$SectionsBlock
"@
}

function Get-NormalizedAction {
    param([string]$Action)

    $Allowed = @(
        "no_change",
        "light_polish",
        "medium_polish",
        "compress",
        "rewrite_opening",
        "rewrite_section",
        "academic_style_fix",
        "terminology_fix",
        "mixed_revision"
    )

    if ([string]::IsNullOrWhiteSpace($Action)) {
        return "medium_polish"
    }

    $Value = $Action.Trim()
    if ($Allowed -contains $Value) {
        return $Value
    }

    switch -Regex ($Value) {
        "pass|通过|不改|无需" { return "no_change" }
        "opening|开头" { return "rewrite_opening" }
        "rewrite|重写" { return "rewrite_section" }
        "compress|压缩" { return "compress" }
        "academic|引用|学术" { return "academic_style_fix" }
        "term|术语" { return "terminology_fix" }
        "light|轻" { return "light_polish" }
        default { return "medium_polish" }
    }
}

function Get-NormalizedPriority {
    param([string]$Priority)

    if ([string]::IsNullOrWhiteSpace($Priority)) {
        return "P2"
    }

    $Value = $Priority.Trim().ToUpperInvariant()
    if (@("P0", "P1", "P2", "P3") -contains $Value) {
        return $Value
    }

    return "P2"
}

function To-StringArray {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return @()
        }
        return @($Value)
    }

    $Result = @()
    foreach ($Item in $Value) {
        if ($null -ne $Item -and -not [string]::IsNullOrWhiteSpace([string]$Item)) {
            $Result += [string]$Item
        }
    }
    return $Result
}

function Normalize-ReviewItem {
    param(
        [Parameter(Mandatory=$true)]
        $Item,

        [Parameter(Mandatory=$true)]
        [hashtable]$SectionByIndex
    )

    $Index = [int]$Item.chapter_index
    $Section = $SectionByIndex[$Index]
    if ($null -eq $Section) {
        throw "Review item returned unknown chapter_index: $Index"
    }

    $TargetMin = if ($Item.target_cjk_min) { [int]$Item.target_cjk_min } else { 1600 }
    $TargetMax = if ($Item.target_cjk_max) { [int]$Item.target_cjk_max } else { 2100 }
    if ($TargetMax -lt $TargetMin) {
        $TargetMax = $TargetMin + 300
    }

    return [ordered]@{
        chapter_index = $Index
        file = if ($Item.file) { [string]$Item.file } else { $Section.file }
        title = if ($Item.title) { [string]$Item.title } else { $Section.title }
        toc_title = $Section.toc_title
        source_cjk_chars = [int]$Section.metrics.cjk_chars
        source_headings = [int]$Section.metrics.headings
        source_risk_phrase_count = [int]$Section.metrics.risk_phrase_count
        primary_action = Get-NormalizedAction -Action ([string]$Item.primary_action)
        secondary_actions = @(To-StringArray -Value $Item.secondary_actions)
        priority = Get-NormalizedPriority -Priority ([string]$Item.priority)
        editorial_verdict = if ($Item.editorial_verdict) { [string]$Item.editorial_verdict } else { "需要按编辑意见处理。" }
        problems = @(To-StringArray -Value $Item.problems)
        revision_instructions = @(To-StringArray -Value $Item.revision_instructions)
        target_cjk_min = $TargetMin
        target_cjk_max = $TargetMax
        compression_target_percent = if ($Item.compression_target_percent) { [int]$Item.compression_target_percent } else { 0 }
        preserve = @(To-StringArray -Value $Item.preserve)
        do_not_change = @(To-StringArray -Value $Item.do_not_change)
        acceptance_criteria = @(To-StringArray -Value $Item.acceptance_criteria)
        notes_for_04c44 = if ($Item.notes_for_04c44) { [string]$Item.notes_for_04c44 } else { "" }
    }
}

function New-DryRunItem {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Section
    )

    $Action = "no_change"
    $Priority = "P3"
    $Problems = @()
    $Instructions = @()
    $Compression = 0

    if ([int]$Section.metrics.cjk_chars -gt 2200) {
        $Action = "compress"
        $Priority = "P2"
        $Compression = 10
        $Problems += "当前小节字数偏长。"
        $Instructions += "在不改变核心观点和模型衔接的前提下压缩重复铺垫、重复例证和模板化转折。"
    }
    elseif ([int]$Section.metrics.risk_phrase_count -gt 18) {
        $Action = "light_polish"
        $Priority = "P2"
        $Problems += "模板化辨析句式偏多。"
        $Instructions += "减少不是/而是、并非、需要强调等句式，改为正向定义、案例推进或问题追问。"
    }

    if ($Section.chapter_index -eq 5) {
        $Action = "rewrite_opening"
        $Priority = "P1"
        $Problems += "第一章开头需要更强的出版现场感。"
        $Instructions += "只重写前4到6段，用更具体的AI学习现场引入，不改变后文主体结构。"
    }

    return [ordered]@{
        chapter_index = $Section.chapter_index
        file = $Section.file
        title = $Section.title
        toc_title = $Section.toc_title
        source_cjk_chars = [int]$Section.metrics.cjk_chars
        source_headings = [int]$Section.metrics.headings
        source_risk_phrase_count = [int]$Section.metrics.risk_phrase_count
        primary_action = $Action
        secondary_actions = @("academic_style_fix")
        priority = $Priority
        editorial_verdict = if ($Action -eq "no_change") { "当前小节可暂时通过。" } else { "当前小节需要进入修稿清单。" }
        problems = @($Problems)
        revision_instructions = @($Instructions)
        target_cjk_min = 1600
        target_cjk_max = 2100
        compression_target_percent = $Compression
        preserve = @("保留原有标题、核心观点、LTC/MCAR/GOAL术语边界和章节衔接。")
        do_not_change = @("不得扩写为相邻小节，不得新增未经要求的新模型，不得虚构文献。")
        acceptance_criteria = @("修订后观点不变。", "修订后语言更自然、重复句式减少。", "保留学术依据线索。")
        notes_for_04c44 = "DryRun 规则生成的占位审读意见；正式使用前建议运行 AI 审读。"
    }
}

function Get-JsonCountMap {
    param(
        [array]$Items,
        [string]$PropertyName
    )

    $Map = [ordered]@{}
    foreach ($Item in $Items) {
        $Key = [string]$Item[$PropertyName]
        if ([string]::IsNullOrWhiteSpace($Key)) {
            $Key = "(empty)"
        }
        if (-not $Map.Contains($Key)) {
            $Map[$Key] = 0
        }
        $Map[$Key] = [int]$Map[$Key] + 1
    }
    return $Map
}

function Escape-MarkdownCell {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    return ($Text -replace "\|", "/" -replace "`r?`n", " ").Trim()
}

function New-MarkdownReport {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Plan,

        [Parameter(Mandatory=$true)]
        [array]$Items
    )

    $ActionCounts = $Plan.summary.counts_by_primary_action
    $PriorityCounts = $Plan.summary.counts_by_priority
    $Lines = [System.Collections.ArrayList]::new()

    [void]$Lines.Add("# 04B33 编辑审读行动报告")
    [void]$Lines.Add("")
    [void]$Lines.Add("生成时间：$($Plan.generated_at)")
    [void]$Lines.Add("")
    [void]$Lines.Add("书名：$($Plan.book_name)")
    [void]$Lines.Add("")
    [void]$Lines.Add("范围：$($Plan.scope.start_chapter)-$($Plan.scope.end_chapter)，共 $($Plan.scope.section_count) 个写作单元")
    [void]$Lines.Add("")
    [void]$Lines.Add("模型：$($Plan.model)")
    [void]$Lines.Add("")
    [void]$Lines.Add("## 总体统计")
    [void]$Lines.Add("")
    [void]$Lines.Add("按处理动作：")
    foreach ($Key in $ActionCounts.Keys) {
        [void]$Lines.Add("- $Key：$($ActionCounts[$Key])")
    }
    [void]$Lines.Add("")
    [void]$Lines.Add("按优先级：")
    foreach ($Key in $PriorityCounts.Keys) {
        [void]$Lines.Add("- $Key：$($PriorityCounts[$Key])")
    }

    [void]$Lines.Add("")
    [void]$Lines.Add("## 逐节行动清单")
    [void]$Lines.Add("")
    [void]$Lines.Add("| 编号 | 文件 | 标题 | 动作 | 优先级 | 原字数 | 审读结论 |")
    [void]$Lines.Add("|---:|---|---|---|---|---:|---|")
    foreach ($Item in $Items) {
        [void]$Lines.Add("| $($Item.chapter_index) | $($Item.file) | $(Escape-MarkdownCell $Item.title) | $($Item.primary_action) | $($Item.priority) | $($Item.source_cjk_chars) | $(Escape-MarkdownCell $Item.editorial_verdict) |")
    }

    [void]$Lines.Add("")
    [void]$Lines.Add("## 重点修改意见")
    foreach ($Item in $Items) {
        if ($Item.primary_action -eq "no_change") {
            continue
        }
        [void]$Lines.Add("")
        [void]$Lines.Add("### $($Item.file) $($Item.title)")
        [void]$Lines.Add("")
        [void]$Lines.Add("- 动作：$($Item.primary_action)")
        [void]$Lines.Add("- 优先级：$($Item.priority)")
        if ($Item.problems.Count -gt 0) {
            [void]$Lines.Add("- 问题：$($Item.problems -join "；")")
        }
        if ($Item.revision_instructions.Count -gt 0) {
            [void]$Lines.Add("- 修改要求：$($Item.revision_instructions -join "；")")
        }
        if (-not [string]::IsNullOrWhiteSpace($Item.notes_for_04c44)) {
            [void]$Lines.Add("- 给04C44：$($Item.notes_for_04c44)")
        }
    }

    return ($Lines -join "`r`n")
}

if ($BatchSize -lt 1) {
    throw "-BatchSize must be at least 1."
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context

$BookRoot = $Context.BookRoot
$TocPath = Join-Path $BookRoot "01_outline\toc.md"
$ChapterRoot = Join-Path $BookRoot "02_chapters"
$BriefRoot = Join-Path $BookRoot "00_brief"

if (!(Test-Path -LiteralPath $TocPath)) {
    throw "toc.md not found: $TocPath"
}
if (!(Test-Path -LiteralPath $ChapterRoot)) {
    throw "chapter root not found: $ChapterRoot"
}
if ([string]::IsNullOrWhiteSpace($ExternalBriefPath)) {
    $Candidate = Join-Path $BriefRoot "external_editorial_brief.md"
    if (Test-Path -LiteralPath $Candidate) {
        $ExternalBriefPath = $Candidate
    }
}
if ([string]::IsNullOrWhiteSpace($PreviousReviewPath)) {
    $Candidate = Join-Path $BriefRoot "learn_part_editorial_review_20260821.md"
    if (Test-Path -LiteralPath $Candidate) {
        $PreviousReviewPath = $Candidate
    }
}

$ResolvedExternalBriefPath = Resolve-OptionalExistingPath -Path $ExternalBriefPath
$ResolvedPreviousReviewPath = Resolve-OptionalExistingPath -Path $PreviousReviewPath

$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$RunRoot = Join-Path $BookRoot ("logs\editorial_loop\{0}_04b33_editorial_review" -f $RunStamp)
$PromptRoot = Join-Path $RunRoot "batch_prompts"
$RawRoot = Join-Path $RunRoot "batch_raw_outputs"
$JsonRoot = Join-Path $RunRoot "batch_json"
$SnapshotRoot = Join-Path $RunRoot "section_snapshots"
New-Item -ItemType Directory -Path $PromptRoot, $RawRoot, $JsonRoot, $SnapshotRoot -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($OutputJsonPath)) {
    $OutputJsonPath = Join-Path $BriefRoot ("{0}_04b33_revision_actions_{1}.json" -f $ScopeName, $RunStamp)
}
if ([string]::IsNullOrWhiteSpace($OutputReportPath)) {
    $OutputReportPath = Join-Path $BriefRoot ("{0}_04b33_editorial_report_{1}.md" -f $ScopeName, $RunStamp)
}

$StableJsonPath = Join-Path $BriefRoot ("{0}_revision_actions.json" -f $ScopeName)
$StableReportPath = Join-Path $BriefRoot ("{0}_editorial_actions_report.md" -f $ScopeName)

$TocContent = Read-Utf8File -Path $TocPath
$ExternalBriefContent = if (-not [string]::IsNullOrWhiteSpace($ResolvedExternalBriefPath)) {
    Limit-Text -Text (Read-Utf8File -Path $ResolvedExternalBriefPath) -MaxChars 9000
} else {
    ""
}
$PreviousReviewContent = if (-not [string]::IsNullOrWhiteSpace($ResolvedPreviousReviewPath)) {
    Limit-Text -Text (Read-Utf8File -Path $ResolvedPreviousReviewPath) -MaxChars 9000
} else {
    ""
}

$Sections = Get-ScopedTocSections `
    -TocContent $TocContent `
    -ChapterRoot $ChapterRoot `
    -Chapter $Chapter `
    -StartChapter $StartChapter `
    -EndChapter $EndChapter

$SectionRecords = @()
$SectionByIndex = @{}
foreach ($Section in $Sections) {
    if (!(Test-Path -LiteralPath $Section.Path)) {
        throw "chapter file not found for section $($Section.Index): $($Section.Path)"
    }

    $Content = Read-Utf8File -Path $Section.Path
    $Title = Get-FrontMatterValue -Content $Content -Key "title"
    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = $Section.TocTitle
    }
    $TitleMatchesToc = (Normalize-ComparableTitle -Title $Title) -eq (Normalize-ComparableTitle -Title $Section.TocTitle)

    $Metrics = Get-SectionMetrics -Path $Section.Path -Content $Content
    $Record = [ordered]@{
        chapter_index = [int]$Section.Index
        total_sections = [int]$Section.Total
        file = [string]$Section.FileName
        path = [string]$Section.Path
        toc_title = [string]$Section.TocTitle
        title = [string]$Title
        title_matches_toc = [bool]$TitleMatchesToc
        metrics = $Metrics
        content = Limit-Text -Text $Content -MaxChars $MaxSectionChars
    }

    $SectionRecords += [hashtable]$Record
    $SectionByIndex[[int]$Section.Index] = [hashtable]$Record
    Save-Utf8File -Path (Join-Path $SnapshotRoot $Section.FileName) -Content $Content
}

$AllItems = @()
$BatchSummaries = @()
$UsageTotals = [ordered]@{
    input_tokens = 0
    output_tokens = 0
    total_tokens = 0
}

for ($Offset = 0; $Offset -lt $SectionRecords.Count; $Offset += $BatchSize) {
    $BatchNo = [int]([Math]::Floor($Offset / $BatchSize) + 1)
    $BatchRecords = @($SectionRecords[$Offset..([Math]::Min($Offset + $BatchSize - 1, $SectionRecords.Count - 1))])
    $BatchLabel = "{0:D2}" -f $BatchNo

    Write-Output ("[04B33] batch {0}: sections {1}" -f $BatchLabel, (($BatchRecords | ForEach-Object { $_.chapter_index }) -join ","))

    if ($DryRun) {
        $Parsed = [pscustomobject]@{
            batch_summary = "DryRun：根据本地指标生成占位审读意见。"
            items = @($BatchRecords | ForEach-Object { New-DryRunItem -Section $_ })
        }
        Save-Utf8File -Path (Join-Path $JsonRoot ("batch_{0}.json" -f $BatchLabel)) -Content (($Parsed | ConvertTo-Json -Depth 20))
    }
    else {
        $Prompt = New-ReviewPrompt `
            -BookName $BookName `
            -SectionRecords $BatchRecords `
            -ExternalBriefContent $ExternalBriefContent `
            -PreviousReviewContent $PreviousReviewContent `
            -ScopeName $ScopeName

        Save-Utf8File -Path (Join-Path $PromptRoot ("batch_{0}_prompt.md" -f $BatchLabel)) -Content $Prompt

        $Result = Invoke-SageTextGeneration -Prompt $Prompt -ModelName $Model -OutputTokenLimit $MaxTokens
        $UsageTotals.input_tokens += [int]$Result.usage.input_tokens
        $UsageTotals.output_tokens += [int]$Result.usage.output_tokens
        $UsageTotals.total_tokens += [int]$Result.usage.total_tokens

        Save-Utf8File -Path (Join-Path $RawRoot ("batch_{0}_raw.txt" -f $BatchLabel)) -Content $Result.content

        $JsonText = Normalize-AiJsonOutput -Content $Result.content
        Save-Utf8File -Path (Join-Path $JsonRoot ("batch_{0}.json" -f $BatchLabel)) -Content $JsonText
        $Parsed = $JsonText | ConvertFrom-Json
    }

    if ($Parsed.batch_summary) {
        $BatchSummaries += [string]$Parsed.batch_summary
    }

    foreach ($Item in @($Parsed.items)) {
        $AllItems += (Normalize-ReviewItem -Item $Item -SectionByIndex $SectionByIndex)
    }
}

$ReturnedByIndex = @{}
foreach ($Item in $AllItems) {
    $ReturnedByIndex[[int]$Item.chapter_index] = $true
}
foreach ($Section in $SectionRecords) {
    if (-not $ReturnedByIndex.ContainsKey([int]$Section.chapter_index)) {
        $Fallback = [ordered]@{
            chapter_index = [int]$Section.chapter_index
            file = $Section.file
            title = $Section.title
            primary_action = "medium_polish"
            secondary_actions = @("academic_style_fix")
            priority = "P1"
            editorial_verdict = "04B33未收到该节的有效模型审读结果，需进入人工/二次审读。"
            problems = @("模型输出缺少本节 JSON 项。")
            revision_instructions = @("重新运行04B33审读本节，或由人工补充具体编辑意见后再交给04C44。")
            target_cjk_min = 1600
            target_cjk_max = 2100
            compression_target_percent = 0
            preserve = @("保留原有标题、核心观点和章节衔接。")
            do_not_change = @("不得在缺少审读意见时大幅改写。")
            acceptance_criteria = @("补齐有效编辑意见。")
            notes_for_04c44 = "缺少审读结果，04C44应跳过或要求重新审读。"
        }
        $AllItems += (Normalize-ReviewItem -Item ([pscustomobject]$Fallback) -SectionByIndex $SectionByIndex)
    }
}

$AllItems = @($AllItems | Sort-Object { [int]$_["chapter_index"] })

$StartIndex = ($Sections | Select-Object -First 1).Index
$EndIndex = ($Sections | Select-Object -Last 1).Index

$Plan = [ordered]@{
    schema_version = "04B33.editorial_actions.v1"
    generated_by = "04b33-editorial-action-review.ps1"
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    book_name = $BookName
    model = if ($DryRun) { "dry_run_local_rules" } else { $Model }
    dry_run = [bool]$DryRun
    scope = [ordered]@{
        name = $ScopeName
        start_chapter = [int]$StartIndex
        end_chapter = [int]$EndIndex
        section_count = [int]$Sections.Count
    }
    source_paths = [ordered]@{
        book_root = $BookRoot
        toc = $TocPath
        chapter_root = $ChapterRoot
        external_brief = $ResolvedExternalBriefPath
        previous_review = $ResolvedPreviousReviewPath
    }
    output_paths = [ordered]@{
        dated_json = $OutputJsonPath
        stable_json = $StableJsonPath
        dated_report = $OutputReportPath
        stable_report = $StableReportPath
        run_root = $RunRoot
    }
    action_definitions = [ordered]@{
        no_change = "通过，不交给04C44修改。"
        light_polish = "轻修语言，不改变结构和观点。"
        medium_polish = "中度修订，保持主结构但可重组部分段落。"
        compress = "压缩字数，删除重复铺垫和冗余例证。"
        rewrite_opening = "只重写开头若干段，主体不动。"
        rewrite_section = "整节重写，保留标题和核心任务。"
        academic_style_fix = "调整学术支撑段或引用体例。"
        terminology_fix = "统一术语。"
        mixed_revision = "复合修订，04C44需按 revision_instructions 执行。"
    }
    batch_summaries = @($BatchSummaries)
    summary = [ordered]@{
        item_count = [int]$AllItems.Count
        counts_by_primary_action = Get-JsonCountMap -Items $AllItems -PropertyName "primary_action"
        counts_by_priority = Get-JsonCountMap -Items $AllItems -PropertyName "priority"
        input_tokens = [int]$UsageTotals.input_tokens
        output_tokens = [int]$UsageTotals.output_tokens
        total_tokens = [int]$UsageTotals.total_tokens
    }
    items = @($AllItems)
}

$PlanJson = $Plan | ConvertTo-Json -Depth 30
Save-Utf8File -Path $OutputJsonPath -Content $PlanJson
Save-Utf8File -Path $StableJsonPath -Content $PlanJson

$Report = New-MarkdownReport -Plan $Plan -Items $AllItems
Save-Utf8File -Path $OutputReportPath -Content $Report
Save-Utf8File -Path $StableReportPath -Content $Report

$ManifestPath = Join-Path $RunRoot "manifest.json"
$Manifest = [ordered]@{
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    book_name = $BookName
    script = $MyInvocation.MyCommand.Path
    model = if ($DryRun) { "dry_run_local_rules" } else { $Model }
    dry_run = [bool]$DryRun
    scope = $Plan.scope
    output_paths = $Plan.output_paths
    source_paths = $Plan.source_paths
    summary = $Plan.summary
}
Save-Utf8File -Path $ManifestPath -Content ($Manifest | ConvertTo-Json -Depth 20)

$LatestPath = Join-Path $Context.LogRoot "editorial_loop\latest_04b33_editorial_review.json"
Save-Utf8File -Path $LatestPath -Content ($Manifest | ConvertTo-Json -Depth 20)

Write-Output "SUCCESS: 04B33 editorial action review completed."
Write-Output "JSON: $OutputJsonPath"
Write-Output "Stable JSON: $StableJsonPath"
Write-Output "Report: $OutputReportPath"
Write-Output "Stable report: $StableReportPath"
Write-Output "Run folder: $RunRoot"
