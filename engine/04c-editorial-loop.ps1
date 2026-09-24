param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [ValidateSet("Constitution", "Developmental", "Consistency", "Reader", "LineEdit", "FullDiagnostic")]
    [string]$Round = "Developmental",

    [string]$EditorModel = "",

    [string]$AuthorModel = "",

    [int]$Chapter,

    [int]$StartChapter,

    [int]$EndChapter,

    [int]$MaxInputChars = 120000,

    [int]$MaxOutputTokens = 12000,

    [int]$RewriteMaxTokens = 7000,

    [switch]$DryRun,

    [switch]$NoAuthorPlan,

    [switch]$ApplyRewrite,

    [switch]$Force
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
        [string]$Content
    )

    $Parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($Parent) -and !(Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true))
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

function Get-MarkdownBodyText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Normalized = $Content -replace "`r", ""
    if ($Normalized.StartsWith("---`n")) {
        $Match = [regex]::Match($Normalized, "(?s)^---\n.*?\n---\n?")
        if ($Match.Success) {
            return $Normalized.Substring($Match.Length).Trim()
        }
    }

    return $Normalized.Trim()
}

function Get-FirstMarkdownHeadingTitle {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Match = [regex]::Match($Content, '(?m)^\s*#{1,6}\s+(.+?)\s*$')
    if ($Match.Success) {
        return $Match.Groups[1].Value.Trim()
    }

    return ""
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

function New-BookConstitutionContent {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookNameValue,

        [Parameter(Mandatory=$true)]
        [string]$BookTitle,

        [Parameter(Mandatory=$true)]
        [string]$ObjectiveContent,

        [Parameter(Mandatory=$true)]
        [string]$TocContent
    )

    $Text = @"
# BOOK CONSTITUTION

---
file_role: book_constitution
book_name: "$BookNameValue"
title: "$BookTitle"
created_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
constitution_version: "2026-08-21-author-editor-loop-v1"
---

## 1. 这本书为什么写

以 “00_brief/objective.md” 为最高来源，固定本书的写作目的、核心问题、目标读者和价值边界。任何作者AI或编辑AI的建议，都不得让本书偏离这个原始写作目的。

## 2. 核心命题

本节由作者确认后冻结。编辑AI可以质疑表达是否清楚、论证是否充分，但不能轻易替换核心命题。

## 3. 目标读者

本节由作者确认后冻结。读者体验编辑可以指出读者认知负荷过高、案例不足、术语过密，但不能把本书改写成面向完全不同人群的书。

## 4. 不可删除核心

- 原创思想优先于编辑舒适度。
- 编辑AI可以要求补定义、补边界、补证据，但不能因为某个观点“不够标准”就直接删除。
- 作者AI必须保留对最终思想结构的责任。

## 5. 写作风格

- 保持学术性、论证性和可读性之间的平衡。
- 每章观点后应尽量有研究、案例、实践经验或逻辑推演作为支撑。
- 避免空泛口号、模板化总结、过度平滑但失去锋芒的表达。

## 6. 理论严谨度

编辑AI必须区分：

- 已有研究；
- 作者推论；
- 作者原创模型；
- 实践经验；
- 价值判断。

不能把价值判断伪装成研究结论，也不能把原创模型写成已经被学界普遍接受的事实。

## 7. 大众可读性标准

- 重要模型必须解释边界、用途和与其他模型的关系。
- 抽象概念需要案例或场景承接。
- 同一观点重复出现时，必须说明它在当前章节的新作用，否则应建议合并或删除。

## 8. 模型数量与概念边界

编辑AI应持续检查模型是否过多、概念是否重叠、术语是否前后不一致。作者AI可以拒绝删除模型，但必须补充模型之间的关系图或边界说明。

## 9. Author Override

作者AI不能无条件服从编辑AI。每一轮编辑报告之后，作者AI必须输出 Revision Plan，并明确：

- 接受哪些建议；
- 部分接受哪些建议；
- 拒绝哪些建议；
- 拒绝理由是什么；
- 哪些修改会进入下一轮重写。

## 10. 禁止事项

- 禁止把“编辑”简化为润色。
- 禁止为了流畅而消除原创锋芒。
- 禁止把所有章节改成同一种平均、安全、标准的声音。
- 禁止在没有 Revision Plan 的情况下直接大规模重写。
- 禁止在没有备份的情况下覆盖正文。

## 11. 轮次规则

### 第1轮 Developmental Editing

只做结构诊断，不改正文。重点看定位、核心命题、章节结构、重复、删并补。

### 第2轮 Consistency Editing

检查概念一致性、模型一致性、论证一致性、证据类型和语义重复。

### 第3轮 Reader Experience Editing

模拟陌生读者，只检查阅读体验、困惑点、无聊点、案例需求和记忆负担。

### 第4轮 Line Editing

最后才做句子、节奏、术语、引文、标点、图表编号和格式整理。

## 12. 当前 objective.md 快照

~~~markdown
$ObjectiveContent
~~~

## 13. 当前 toc.md 快照

~~~markdown
$TocContent
~~~
"@
    return $Text
}

function Get-RoundInstruction {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RoundName
    )

    if ($RoundName -eq "Developmental") {
        $Text = @"
# Editorial Report 1: Developmental Editing

你是编辑AI，不是润色AI。你禁止改正文，禁止输出重写后的章节。

你的任务是建设性地破坏结构，回答：

1. 本书核心价值是什么？
2. 最大的三个结构问题是什么？
3. 哪些章或小节应该删除？
4. 哪些章或小节应该合并？
5. 哪些概念重复？
6. 哪些论证缺失？
7. 哪些地方偏离目标读者？
8. 建议修改后的目录是什么？
9. 哪些问题必须由作者AI决定，不能由编辑AI越权决定？

输出必须是 “Editorial Report 1”，只给诊断和建议，不给改写正文。
"@
        return $Text
    }

    if ($RoundName -eq "Consistency") {
        $Text = @"
# Editorial Report 2: Argument and Consistency Review

你是知情编辑AI。你知道本书目标、理论体系和全书上下文。你禁止改正文。

重点检查：

1. 概念一致性：同一术语在不同章节是否含义漂移。
2. 模型一致性：不同模型之间是否重叠、冲突或缺少关系说明。
3. 论证一致性：前后章节是否互相抵触。
4. 证据类型：已有研究、作者推论、原创模型、实践经验、价值判断是否混在一起。
5. 语义重复：同一观点是否在不同章节用不同说法重复出现。
6. 术语统一：同一概念是否有多个名称。

输出必须是 “Editorial Report 2”，按严重程度排序，并给出可执行修改建议。
"@
        return $Text
    }

    if ($RoundName -eq "Reader") {
        $Text = @"
# Editorial Report 3: Reader Experience Review

你是陌生读者模式的编辑AI。你不是专家，不替作者补脑内逻辑。你只根据拿到的章节判断第一次阅读体验。

逐章回答：

1. 前几页能否吸引你？
2. 你第一次感到困难的位置在哪里？
3. 哪个概念记不住？
4. 哪一章或哪一节最无聊？
5. 哪些段落像重复？
6. 哪些地方需要案例？
7. 哪些理论可以放到脚注或附录？
8. 哪个观点值得画成图？
9. 哪一句可能成为全书金句？

输出必须是 “Editorial Report 3”，强调读者体验，不做学术审稿式扩写。
"@
        return $Text
    }

    if ($RoundName -eq "LineEdit") {
        $Text = @"
# Editorial Report 4: Final Line Editing Checklist

你是文字编辑AI。只有在结构、论证和读者体验完成之后，才进入本轮。

检查：

1. 句子压缩；
2. 段落节奏；
3. 模板句清除；
4. 术语统一；
5. 标题重写建议；
6. 引文规范；
7. 标点；
8. 图表编号；
9. 参考文献格式；
10. Markdown 和成书格式风险。

输出必须是 “Editorial Report 4”，不要重写全文，只列出应修改的类型、位置和理由。
"@
        return $Text
    }

    return ""
}

function Get-ScopedChapterFiles {
    param(
        [Parameter(Mandatory=$true)]
        [object[]]$ChapterFiles
    )

    $Total = $ChapterFiles.Count
    if ($Total -eq 0) {
        return @()
    }

    if ($Chapter -and ($StartChapter -or $EndChapter)) {
        throw "Cannot combine -Chapter with -StartChapter/-EndChapter."
    }

    if ($Chapter) {
        if ($Chapter -lt 1 -or $Chapter -gt $Total) {
            throw "Chapter out of range. Total chapter files: $Total."
        }
        return @($ChapterFiles[$Chapter - 1])
    }

    if ($StartChapter -or $EndChapter) {
        if (-not $StartChapter -or -not $EndChapter) {
            throw "Both -StartChapter and -EndChapter must be specified."
        }
        if ($StartChapter -lt 1 -or $EndChapter -gt $Total -or $StartChapter -gt $EndChapter) {
            throw "Invalid chapter range. Total chapter files: $Total."
        }
        return @($ChapterFiles[($StartChapter - 1)..($EndChapter - 1)])
    }

    return @($ChapterFiles)
}

function New-ManuscriptDigest {
    param(
        [Parameter(Mandatory=$true)]
        [object[]]$Files,

        [Parameter(Mandatory=$true)]
        [int]$CharLimit
    )

    $Builder = New-Object System.Text.StringBuilder
    $Remaining = $CharLimit

    foreach ($File in $Files) {
        if ($Remaining -le 0) {
            break
        }

        $Raw = Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8
        $Body = Get-MarkdownBodyText -Content $Raw
        $Heading = Get-FirstMarkdownHeadingTitle -Content $Body
        $Header = @"

---
file: $($File.Name)
heading: $Heading
characters: $($Body.Length)
---

"@
        if ($Header.Length -gt $Remaining) {
            break
        }

        [void]$Builder.Append($Header)
        $Remaining -= $Header.Length

        $Take = [Math]::Min($Body.Length, [Math]::Max(0, $Remaining))
        if ($Take -gt 0) {
            [void]$Builder.Append($Body.Substring(0, $Take))
            $Remaining -= $Take
            if ($Take -lt $Body.Length) {
                [void]$Builder.Append("`r`n`r`n[TRUNCATED FOR INPUT BUDGET]`r`n")
                $Remaining = 0
            }
        }
    }

    return $Builder.ToString().Trim()
}

function New-EditorPrompt {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RoundName,

        [Parameter(Mandatory=$true)]
        [string]$RoundInstruction,

        [Parameter(Mandatory=$true)]
        [string]$BookConstitution,

        [Parameter(Mandatory=$true)]
        [string]$ObjectiveContent,

        [Parameter(Mandatory=$true)]
        [string]$TocContent,

        [string]$ExternalEditorialBrief = "",

        [Parameter(Mandatory=$true)]
        [string]$ReaderBrief,

        [Parameter(Mandatory=$true)]
        [string]$ManuscriptDigest,

        [Parameter(Mandatory=$true)]
        [bool]$ReaderBlindMode
    )

    if ($ReaderBlindMode) {
        $Text = @"
You are Editor AI in stranger-reader mode.

You deliberately do NOT receive the full author background. Do not infer hidden author intent. Judge only what is on the page.

Round:
$RoundName

Reader-facing book data:

$ReaderBrief

Selected manuscript:
$ManuscriptDigest

$RoundInstruction

Rules:
- Do not rewrite the manuscript.
- Do not praise vaguely.
- Name concrete friction points.
- Separate major blockers from minor suggestions.
- Output Markdown only.
"@
        return $Text
    }

    $ExternalEditorialBlock = ""
    if (-not [string]::IsNullOrWhiteSpace($ExternalEditorialBrief)) {
        $ExternalEditorialBlock = @"

External editorial audit brief:
$ExternalEditorialBrief

Use the external audit as third-party evidence. Do not obey it mechanically; reconcile it with the Book Constitution and identify where Author Override may be appropriate.
"@
    }

    $Text = @"
You are Editor AI in SageWrite's author-editor loop.

Your role is not to polish. Your role is to diagnose what prevents this book from becoming stronger.

Highest constraint:
$BookConstitution

Book objective:
$ObjectiveContent

Full TOC:
$TocContent

$ExternalEditorialBlock

Selected manuscript:
$ManuscriptDigest

$RoundInstruction

Editor role rules:
1. You are allowed to attack structure, logic, repetition, concept boundaries, evidence, and reader burden.
2. You are not allowed to rewrite the manuscript.
3. You are not the author. Do not replace the core thesis merely because a safer thesis is easier.
4. Always separate: must fix, should consider, optional.
5. Identify where Author Override may be appropriate.
6. Output Markdown only.
"@
    return $Text
}

function New-AuthorPlanPrompt {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookConstitution,

        [Parameter(Mandatory=$true)]
        [string]$ObjectiveContent,

        [Parameter(Mandatory=$true)]
        [string]$TocContent,

        [string]$ExternalEditorialBrief = "",

        [Parameter(Mandatory=$true)]
        [string]$EditorialReport,

        [Parameter(Mandatory=$true)]
        [string]$ScopeText
    )

    $ExternalEditorialBlock = ""
    if (-not [string]::IsNullOrWhiteSpace($ExternalEditorialBrief)) {
        $ExternalEditorialBlock = @"

External editorial audit brief:
$ExternalEditorialBrief

Use this as third-party editorial evidence. For every high-priority external recommendation, decide whether to accept, partially accept, or reject through Author Override.
"@
    }

    $Text = @"
You are Author AI in SageWrite's author-editor loop.

Your job is NOT to obey the editor mechanically. Your job is to protect and strengthen the author's core thought while accepting useful criticism.

Highest constraint:
$BookConstitution

Book objective:
$ObjectiveContent

TOC:
$TocContent

$ExternalEditorialBlock

Editorial report:
$EditorialReport

Scope:
$ScopeText

Create a Revision Plan.

Required structure:

# Revision Plan

## 1. Accepted Suggestions

List the editor suggestions accepted without reservation and why.

## 2. Partially Accepted Suggestions

List suggestions accepted with boundaries or modifications.

## 3. Rejected Suggestions / Author Override

List suggestions rejected because they damage the core thesis, voice, originality, or target reader. Explain why.

## 4. Structural Actions

List chapter/section-level actions: delete, merge, move, expand, add evidence, add cases, clarify concepts.

## 5. Concept and Evidence Actions

List terminology, model relationship, evidence, citation, and argument fixes.

## 6. Rewrite Instructions for 03-write

Write concise operational instructions that can be passed to “03-write.ps1 -AdditionalInstructions”.

Rules:
- Preserve authorial ownership.
- Do not produce rewritten chapter text.
- Output Markdown only.
"@
    return $Text
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "editorial_loop" -Data @{
    round = $Round
    editor_model = $EditorModel
    author_model = $AuthorModel
    chapter = $Chapter
    start_chapter = $StartChapter
    end_chapter = $EndChapter
    dry_run = [bool]$DryRun
    no_author_plan = [bool]$NoAuthorPlan
    apply_rewrite = [bool]$ApplyRewrite
}

$BookRoot = $Context.BookRoot
$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
$TocPath = Join-Path $BookRoot "01_outline\toc.md"
$ChapterRoot = Join-Path $BookRoot "02_chapters"
$ConstitutionPath = Join-Path $BookRoot "00_brief\book_constitution.md"
$ExternalEditorialBriefPath = Join-Path $BookRoot "00_brief\external_editorial_brief.md"
$RevisionPlanRoot = Join-Path $BookRoot "00_brief\revision_plans"
$LoopRoot = Join-Path $Context.LogRoot "editorial_loop"
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$RunRoot = Join-Path $LoopRoot $RunStamp
$PromptRoot = Join-Path $RunRoot "prompts"

try {
    if (!(Test-Path -LiteralPath $ObjectivePath)) {
        throw "objective.md not found: $ObjectivePath"
    }
    if (!(Test-Path -LiteralPath $TocPath)) {
        throw "toc.md not found: $TocPath"
    }
    if (!(Test-Path -LiteralPath $ChapterRoot)) {
        throw "02_chapters folder not found: $ChapterRoot"
    }

    $ObjectiveContent = Get-Content -LiteralPath $ObjectivePath -Raw -Encoding UTF8
    $TocContent = Get-Content -LiteralPath $TocPath -Raw -Encoding UTF8
    $ExternalEditorialBrief = ""
    if (Test-Path -LiteralPath $ExternalEditorialBriefPath) {
        $ExternalEditorialBrief = Get-Content -LiteralPath $ExternalEditorialBriefPath -Raw -Encoding UTF8
        Write-Output "External editorial brief loaded:"
        Write-Output $ExternalEditorialBriefPath
    }

    $BookTitle = Get-FrontMatterValue -Content $ObjectiveContent -Key "title"
    if ([string]::IsNullOrWhiteSpace($BookTitle)) {
        $BookTitle = $BookName
    }
    $Audience = Get-FrontMatterValue -Content $ObjectiveContent -Key "audience"
    if ([string]::IsNullOrWhiteSpace($Audience)) {
        $Audience = Get-FrontMatterValue -Content $ObjectiveContent -Key "target_reader"
    }
    if ([string]::IsNullOrWhiteSpace($Audience)) {
        $Audience = "未在 objective.md front matter 中明确写出。"
    }
    $ReaderBrief = @"
Book title: $BookTitle
Target reader: $Audience

Do not use hidden author background. Judge whether the selected manuscript itself explains enough.
"@

    if (!(Test-Path -LiteralPath $ConstitutionPath) -or $Force) {
        $ConstitutionContent = New-BookConstitutionContent -BookNameValue $BookName -BookTitle $BookTitle -ObjectiveContent $ObjectiveContent -TocContent $TocContent
        if (-not $DryRun) {
            Save-Utf8File -Path $ConstitutionPath -Content $ConstitutionContent
            Write-Output "Book Constitution saved:"
            Write-Output $ConstitutionPath
        }
    }
    else {
        $ConstitutionContent = Get-Content -LiteralPath $ConstitutionPath -Raw -Encoding UTF8
    }

    if ($Round -eq "Constitution") {
        Complete-SageStep -Context $Context -Step "editorial_loop" -State "success" -Message "Book Constitution prepared." -Data @{
            constitution = $ConstitutionPath
            dry_run = [bool]$DryRun
        }
        Write-Output "SUCCESS: Book Constitution prepared."
        if ($DryRun) {
            Write-Output "Dry run only. No file was written."
        }
        exit 0
    }

    $AllChapterFiles = @(Get-ChildItem -LiteralPath $ChapterRoot -Filter *.md -File |
        Where-Object { $_.Name -notmatch "^_" } |
        Sort-Object Name)
    $ScopedFiles = @(Get-ScopedChapterFiles -ChapterFiles $AllChapterFiles)
    if ($ScopedFiles.Count -eq 0) {
        throw "No chapter files found for selected scope."
    }

    $FirstIndex = [Array]::IndexOf($AllChapterFiles, $ScopedFiles[0]) + 1
    $LastIndex = [Array]::IndexOf($AllChapterFiles, $ScopedFiles[$ScopedFiles.Count - 1]) + 1
    $ScopeText = "chapter_files=$($ScopedFiles.Count); range=$FirstIndex-$LastIndex; files=" + (($ScopedFiles | Select-Object -ExpandProperty Name) -join ", ")
    $ManuscriptDigest = New-ManuscriptDigest -Files $ScopedFiles -CharLimit $MaxInputChars

    New-Item -ItemType Directory -Path $PromptRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $RevisionPlanRoot -Force | Out-Null

    $RoundsToRun = if ($Round -eq "FullDiagnostic") {
        @("Developmental", "Consistency", "Reader", "LineEdit")
    }
    else {
        @($Round)
    }

    $ReportPaths = @()
    $PlanPaths = @()
    $TotalInputTokens = 0
    $TotalOutputTokens = 0
    $TotalTokens = 0

    foreach ($RoundName in $RoundsToRun) {
        $RoundInstruction = Get-RoundInstruction -RoundName $RoundName
        $ReaderBlindMode = ($RoundName -eq "Reader")
        $EditorPrompt = New-EditorPrompt `
            -RoundName $RoundName `
            -RoundInstruction $RoundInstruction `
            -BookConstitution $ConstitutionContent `
            -ObjectiveContent $ObjectiveContent `
            -TocContent $TocContent `
            -ExternalEditorialBrief $ExternalEditorialBrief `
            -ReaderBrief $ReaderBrief `
            -ManuscriptDigest $ManuscriptDigest `
            -ReaderBlindMode $ReaderBlindMode

        $EditorPromptPath = Join-Path $PromptRoot ("editor_{0}.md" -f $RoundName.ToLowerInvariant())
        Save-Utf8File -Path $EditorPromptPath -Content $EditorPrompt

        $ReportPath = Join-Path $RunRoot ("editorial_report_{0}.md" -f $RoundName.ToLowerInvariant())
        if ($DryRun) {
            Save-Utf8File -Path $ReportPath -Content "# Editorial Report Placeholder`r`n`r`nDry run only. Prompt saved to:`r`n`r`n$EditorPromptPath"
            Write-Output "Dry run: editor prompt saved for $RoundName"
        }
        else {
            Write-Output "Editor AI running: $RoundName"
            $EditorResult = Invoke-SageTextGeneration -Prompt $EditorPrompt -ModelName $EditorModel -OutputTokenLimit $MaxOutputTokens
            Save-Utf8File -Path $ReportPath -Content $EditorResult.content
            $TotalInputTokens += $EditorResult.usage.input_tokens
            $TotalOutputTokens += $EditorResult.usage.output_tokens
            $TotalTokens += $EditorResult.usage.total_tokens
            Write-Output "Editorial report saved: $ReportPath"
        }
        $ReportPaths += $ReportPath

        if (-not $NoAuthorPlan) {
            $ReportContent = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8
            $AuthorPrompt = New-AuthorPlanPrompt `
                -BookConstitution $ConstitutionContent `
                -ObjectiveContent $ObjectiveContent `
                -TocContent $TocContent `
                -ExternalEditorialBrief $ExternalEditorialBrief `
                -EditorialReport $ReportContent `
                -ScopeText $ScopeText

            $AuthorPromptPath = Join-Path $PromptRoot ("author_revision_plan_{0}.md" -f $RoundName.ToLowerInvariant())
            Save-Utf8File -Path $AuthorPromptPath -Content $AuthorPrompt

            $PlanPath = Join-Path $RunRoot ("revision_plan_{0}.md" -f $RoundName.ToLowerInvariant())
            $BriefPlanPath = Join-Path $RevisionPlanRoot ("{0}_{1}.md" -f $RunStamp, $RoundName.ToLowerInvariant())

            if ($DryRun) {
                $PlanPlaceholder = "# Revision Plan Placeholder`r`n`r`nDry run only. Prompt saved to:`r`n`r`n$AuthorPromptPath"
                Save-Utf8File -Path $PlanPath -Content $PlanPlaceholder
                Save-Utf8File -Path $BriefPlanPath -Content $PlanPlaceholder
                Write-Output "Dry run: author prompt saved for $RoundName"
            }
            else {
                Write-Output "Author AI planning: $RoundName"
                $AuthorResult = Invoke-SageTextGeneration -Prompt $AuthorPrompt -ModelName $AuthorModel -OutputTokenLimit $MaxOutputTokens
                Save-Utf8File -Path $PlanPath -Content $AuthorResult.content
                Save-Utf8File -Path $BriefPlanPath -Content $AuthorResult.content
                $TotalInputTokens += $AuthorResult.usage.input_tokens
                $TotalOutputTokens += $AuthorResult.usage.output_tokens
                $TotalTokens += $AuthorResult.usage.total_tokens
                Write-Output "Revision plan saved: $PlanPath"
            }

            $PlanPaths += $PlanPath
        }
    }

    if ($ApplyRewrite) {
        if ($DryRun) {
            Write-Output "Dry run: ApplyRewrite requested, but no rewrite was executed."
        }
        elseif ($PlanPaths.Count -eq 0) {
            throw "-ApplyRewrite requires an author Revision Plan. Remove -NoAuthorPlan."
        }
        else {
            $CombinedPlanSections = foreach ($PlanPath in $PlanPaths) {
                $PlanName = [System.IO.Path]::GetFileNameWithoutExtension($PlanPath)
                $PlanContent = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8
                "## $PlanName`r`n`r`n$PlanContent"
            }
            $RewriteInstructions = @"
# Editorial Loop Rewrite Instructions

Scope:
$ScopeText

Use all accepted decisions below as binding rewrite instructions.
Treat rejected suggestions as Author Override decisions, and preserve the book's original thesis unless the plan explicitly changes it.

$($CombinedPlanSections -join "`r`n`r`n---`r`n`r`n")
"@
            $RewriteInstructionPath = Join-Path $RunRoot "rewrite_instructions.md"
            Save-Utf8File -Path $RewriteInstructionPath -Content $RewriteInstructions

            $BackupRoot = Join-Path $ChapterRoot "back"
            $RewriteBackupRoot = Join-Path $BackupRoot ("editorial_loop_rewrite_{0}" -f $RunStamp)
            New-Item -ItemType Directory -Path $RewriteBackupRoot -Force | Out-Null

            foreach ($File in $ScopedFiles) {
                Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $RewriteBackupRoot $File.Name) -Force
            }

            $WriteScript = Join-Path $Context.EnginePath "03-write.ps1"
            $WriteArgs = @(
                "-BookName", $BookName,
                "-Model", $AuthorModel,
                "-MaxTokens", ([string]$RewriteMaxTokens),
                "-AdditionalInstructions", $RewriteInstructions,
                "-Force"
            )
            if ($Chapter) {
                $WriteArgs += @("-Chapter", ([string]$Chapter))
            }
            else {
                $WriteArgs += @("-StartChapter", ([string]$FirstIndex), "-EndChapter", ([string]$LastIndex))
            }

            Write-Output "Applying rewrite through 03-write.ps1..."
            & $WriteScript @WriteArgs
            if ($LASTEXITCODE -ne 0) {
                throw "03-write.ps1 failed during ApplyRewrite."
            }
            Write-Output "Rewrite backup saved: $RewriteBackupRoot"
        }
    }

    $ManifestPath = Join-Path $RunRoot "manifest.json"
    $Manifest = [ordered]@{
        generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        book_name = $BookName
        round = $Round
        rounds_run = $RoundsToRun
        scope = $ScopeText
        dry_run = [bool]$DryRun
        constitution = $ConstitutionPath
        external_editorial_brief = $(if (-not [string]::IsNullOrWhiteSpace($ExternalEditorialBrief)) { $ExternalEditorialBriefPath } else { "" })
        external_editorial_brief_loaded = (-not [string]::IsNullOrWhiteSpace($ExternalEditorialBrief))
        reports = $ReportPaths
        revision_plans = $PlanPaths
        prompt_root = $PromptRoot
        editor_model = $EditorModel
        author_model = $AuthorModel
        apply_rewrite = [bool]$ApplyRewrite
        run_root = $RunRoot
        usage = @{
            input_tokens = $TotalInputTokens
            output_tokens = $TotalOutputTokens
            total_tokens = $TotalTokens
        }
    }
    $Manifest | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $ManifestPath -Encoding utf8

    $LatestManifestPath = Join-Path $LoopRoot "latest.json"
    $Manifest | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $LatestManifestPath -Encoding utf8

    Complete-SageStep -Context $Context -Step "editorial_loop" -State "success" -Message "Editorial loop completed." -Data @{
        round = $Round
        rounds_run = $RoundsToRun
        reports = $ReportPaths
        revision_plans = $PlanPaths
        manifest = $ManifestPath
        dry_run = [bool]$DryRun
        apply_rewrite = [bool]$ApplyRewrite
        external_editorial_brief_loaded = (-not [string]::IsNullOrWhiteSpace($ExternalEditorialBrief))
        input_tokens_total = $TotalInputTokens
        output_tokens_total = $TotalOutputTokens
        total_tokens_total = $TotalTokens
    }

    Write-Output "SUCCESS: Editorial loop completed."
    Write-Output "Run folder: $RunRoot"
    Write-Output "Reports: $($ReportPaths.Count)"
    Write-Output "Revision plans: $($PlanPaths.Count)"
    Write-Output "Manifest: $ManifestPath"
    if ($DryRun) {
        Write-Output "Dry run only. Prompts were saved but no AI calls were made."
    }
}
catch {
    Fail-SageStep -Context $Context -Step "editorial_loop" -Message "Editorial loop failed." -Data @{
        round = $Round
        error = $_.Exception.Message
    }
    Write-Output "ERROR: Editorial loop failed."
    Write-Output "DETAIL: $($_.Exception.Message)"
    exit 1
}
