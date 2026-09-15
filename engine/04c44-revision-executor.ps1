param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Model = "gpt-5.5",

    [string]$PlanPath,

    [int]$Chapter,

    [int]$StartChapter,

    [int]$EndChapter,

    [int]$MaxTokens = 8000,

    [int]$MaxExistingChars = 14000,

    [string]$ScopeName = "learn_part",

    [switch]$DryRun
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

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

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

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

    return $Text.Substring(0, $MaxChars) + "`r`n`r`n[04C44 truncated the source text in this prompt. Preserve the supplied structure and follow the revision brief.]"
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

function Invoke-SageTextGeneration {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,

        [Parameter(Mandatory=$true)]
        [string]$ModelName,

        [Parameter(Mandatory=$true)]
        [int]$OutputTokenLimit
    )

    $BodyObject = @{
        model = $ModelName
        input = $Prompt
        max_output_tokens = $OutputTokenLimit
    }

    $JsonString = $BodyObject | ConvertTo-Json -Depth 10 -Compress
    $Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonString)

    $Response = Invoke-RestMethod `
        -Uri "https://api.openai.com/v1/responses" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $env:OPENAI_API_KEY"
            "Content-Type"  = "application/json; charset=utf-8"
        } `
        -Body $Utf8Bytes

    $OutputText = ""
    foreach ($Item in $Response.output) {
        foreach ($Content in $Item.content) {
            if ($Content.type -eq "output_text") {
                $OutputText += $Content.text
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($OutputText)) {
        throw "AI response was empty."
    }

    $InputTokens = 0
    $OutputTokens = 0
    $TotalTokens = 0
    if ($Response.usage) {
        if ($null -ne $Response.usage.input_tokens) {
            $InputTokens = [int]$Response.usage.input_tokens
        }
        if ($null -ne $Response.usage.output_tokens) {
            $OutputTokens = [int]$Response.usage.output_tokens
        }
        if ($null -ne $Response.usage.total_tokens) {
            $TotalTokens = [int]$Response.usage.total_tokens
        }
    }

    return @{
        content = (Normalize-MarkdownOutput -Content $OutputText)
        usage = @{
            input_tokens = $InputTokens
            output_tokens = $OutputTokens
            total_tokens = $TotalTokens
        }
    }
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

function Get-TextMetrics {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $RiskPhraseCount = 0
    foreach ($Phrase in @("不是", "而是", "并非", "不能", "需要强调", "需要注意", "由此看", "从这个意义上说", "学术支撑", "可以概括为")) {
        $RiskPhraseCount += Count-Pattern -Text $Content -Pattern ([regex]::Escape($Phrase))
    }

    return [ordered]@{
        cjk_chars = Count-Pattern -Text $Content -Pattern "[\u4e00-\u9fff]"
        headings = Count-Pattern -Text $Content -Pattern "(?m)^#{3,4}\s+"
        risk_phrase_count = $RiskPhraseCount
        not_count = Count-Pattern -Text $Content -Pattern "不是"
        academic_support_count = Count-Pattern -Text $Content -Pattern "学术支撑"
        mcar_count = Count-Pattern -Text $Content -Pattern "MCAR"
        goal_count = Count-Pattern -Text $Content -Pattern "GOAL"
        ltc_count = Count-Pattern -Text $Content -Pattern "LTC"
        ai_count = Count-Pattern -Text $Content -Pattern "AI"
    }
}

function Get-FrontMatter {
    param([string]$Content)

    $Normalized = $Content -replace "`r", ""
    $Match = [regex]::Match($Normalized, "(?s)^---\n(.*?)\n---\n?")
    if (-not $Match.Success) {
        return ""
    }

    return $Match.Groups[1].Value
}

function Remove-FrontMatter {
    param([string]$Content)

    $Normalized = $Content.Trim()
    if ($Normalized -match '^(?s)---\r?\n.*?\r?\n---\r?\n?(.*)$') {
        return $Matches[1].Trim()
    }

    return $Normalized
}

function Escape-YamlString {
    param([string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return ($Text -replace "\\", "\\" -replace '"', '\"')
}

function New-FrontMatter {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OriginalContent,

        [Parameter(Mandatory=$true)]
        $Item,

        [Parameter(Mandatory=$true)]
        [string]$ModelName,

        [Parameter(Mandatory=$true)]
        [string]$RunStamp,

        [string]$TitleOverride
    )

    $OriginalFront = Get-FrontMatter -Content $OriginalContent
    $Lines = @()

    if (-not [string]::IsNullOrWhiteSpace($OriginalFront)) {
        foreach ($Line in ($OriginalFront -split "`n")) {
            $Trimmed = $Line.Trim()
            if ($Trimmed -match '^(revised_at|revision_model|revision_action|revision_source|revision_run)\s*:') {
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace($TitleOverride) -and $Trimmed -match '^title\s*:') {
                continue
            }
            $Lines += $Line.TrimEnd()
        }
    }
    else {
        $Lines += "file_role: chapter"
        $Lines += ("chapter_index: {0}" -f [int]$Item.chapter_index)
        $Lines += ('title: "{0}"' -f (Escape-YamlString ([string]$Item.title)))
    }

    if (-not [string]::IsNullOrWhiteSpace($TitleOverride)) {
        $Lines += ('title: "{0}"' -f (Escape-YamlString $TitleOverride))
    }
    $Lines += ('revised_at: "{0}"' -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    $Lines += ('revision_model: "{0}"' -f (Escape-YamlString $ModelName))
    $Lines += ('revision_action: "{0}"' -f (Escape-YamlString ([string]$Item.primary_action)))
    $Lines += 'revision_source: "04C44"'
    $Lines += ('revision_run: "{0}"' -f $RunStamp)

    return "---`r`n$($Lines -join "`r`n")`r`n---"
}

function Get-FirstSectionHeading {
    param([string]$Content)

    $Match = [regex]::Match($Content, "(?m)^###\s+(.+?)\s*$")
    if ($Match.Success) {
        return $Match.Groups[1].Value.Trim()
    }

    return ""
}

function Allows-TitleOverride {
    param($Item)

    $Action = [string]$Item.primary_action
    if (@("title_fix", "terminology_fix") -contains $Action) {
        return $true
    }

    foreach ($Secondary in (To-StringArray -Value $Item.secondary_actions)) {
        if (@("title_fix", "terminology_fix") -contains $Secondary) {
            return $true
        }
    }

    return $false
}

function Merge-RevisedBody {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OriginalContent,

        [Parameter(Mandatory=$true)]
        [string]$AiContent,

        [Parameter(Mandatory=$true)]
        $Item,

        [Parameter(Mandatory=$true)]
        [string]$ModelName,

        [Parameter(Mandatory=$true)]
        [string]$RunStamp
    )

    $Body = Remove-FrontMatter -Content $AiContent
    if ([string]::IsNullOrWhiteSpace($Body)) {
        throw "AI revision body was empty after front matter removal."
    }

    $TitleOverride = ""
    if (Allows-TitleOverride -Item $Item) {
        $TitleOverride = Get-FirstSectionHeading -Content $Body
    }

    $Front = New-FrontMatter -OriginalContent $OriginalContent -Item $Item -ModelName $ModelName -RunStamp $RunStamp -TitleOverride $TitleOverride
    return "$Front`r`n`r`n$($Body.Trim())`r`n"
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

function Get-ActionGuidance {
    param($Item)

    $Action = [string]$Item.primary_action
    switch ($Action) {
        "light_polish" {
            return "轻修：只改善句子、连接和少量重复表达。不得调整结构，不得改变观点。"
        }
        "medium_polish" {
            return "中度修订：可以重组局部段落、减少模板化句式、压缩轻微重复，但必须保留原节结构和核心观点。"
        }
        "compress" {
            $Percent = if ($Item.compression_target_percent) { [int]$Item.compression_target_percent } else { 10 }
            return "压缩：目标压缩约 $Percent%。删除重复铺垫、过长并列案例和重复模型回扣，保留核心观点、关键案例和章节衔接。"
        }
        "rewrite_opening" {
            return "开头局部重写：只重写开头4到6段，使其更有出版现场感；主体结构和主体内容保持，只做必要衔接。"
        }
        "rewrite_section" {
            return "整节重写：保留标题、写作单元任务、核心观点、模型边界和应有衔接，重新组织全文。不得扩写相邻小节。"
        }
        "academic_style_fix" {
            return "学术体例修订：重点把节末'学术支撑说明'改为正式出版语气。保留来源线索，不虚构文献，不把内部审稿提示直接留在正文。"
        }
        "terminology_fix" {
            return "术语统一：优先统一LTC、Learn、Tech、Create、学习力、技术赋能能力、创造能力、MCAR、GOAL等术语，不改变正文结构。"
        }
        "mixed_revision" {
            return "复合修订：按04B33的具体 revision_instructions 执行，通常包含压缩、术语统一、语言降重和学术体例处理。"
        }
        default {
            return "按编辑意见做保守修订。"
        }
    }
}

function New-RevisionPrompt {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookName,

        [Parameter(Mandatory=$true)]
        $Item,

        [Parameter(Mandatory=$true)]
        [string]$OriginalContent
    )

    $ItemJson = $Item | ConvertTo-Json -Depth 20
    $ActionGuidance = Get-ActionGuidance -Item $Item
    $RevisionInstructions = (To-StringArray -Value $Item.revision_instructions) -join "`r`n- "
    $Problems = (To-StringArray -Value $Item.problems) -join "`r`n- "
    $Preserve = (To-StringArray -Value $Item.preserve) -join "`r`n- "
    $DoNotChange = (To-StringArray -Value $Item.do_not_change) -join "`r`n- "
    $Acceptance = (To-StringArray -Value $Item.acceptance_criteria) -join "`r`n- "

    return @"
你是 SageWrite 工作流中的 04C44：出版修稿执行 AI。

你的任务：根据 04B33 编辑审读 JSON，对一个已经生成的小节执行修稿。你不是重新审稿，不要自行扩大任务；你只落实给定编辑意见。

书名：$BookName
文件：$($Item.file)
标题：$($Item.title)
动作：$($Item.primary_action)
优先级：$($Item.priority)

动作解释：
$ActionGuidance

硬性要求：
1. 只输出修订后的完整 Markdown 文件内容，不要解释，不要代码围栏。
2. 保留 YAML front matter 的基本信息。即使你输出 front matter，程序也会恢复原始元数据并添加 revision 字段。
3. 默认保留原小节标题；只有当 04B33 明确要求 title_fix 或 terminology_fix 且要求调整标题时，才允许按编辑意见修改本节标题。不得写相邻小节，不得新增章节。
4. 不得虚构文献、页码、DOI、实验数据或机构报告。学术依据只能保留为可核验来源线索。
5. 不得破坏 LTC / Learn / Tech / Create / MCAR / GOAL 的既定边界。
6. 不得把“04B33”“04C44”“编辑意见”“JSON”“本次修订”等流程性文字写进正文。
7. 修订后中文主体字数尽量落在 $($Item.target_cjk_min)-$($Item.target_cjk_max) 字之间；如因保留必要内容略超，优先保证结构完整。
8. 对 no_change 动作不应进入本提示；若误入，请原样输出正文。

04B33 结构化编辑意见：
$ItemJson

具体问题：
- $Problems

具体修改要求：
- $RevisionInstructions

必须保留：
- $Preserve

禁止改动：
- $DoNotChange

验收标准：
- $Acceptance

原稿内容：
$OriginalContent
"@
}

function Add-BackupFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,

        [Parameter(Mandatory=$true)]
        [string]$BackupRoot,

        [Parameter(Mandatory=$true)]
        [string]$RelativePath,

        [System.Collections.ArrayList]$Records
    )

    if (!(Test-Path -LiteralPath $SourcePath)) {
        return
    }

    $Destination = Join-Path $BackupRoot $RelativePath
    $DestinationParent = Split-Path -Parent $Destination
    if (!(Test-Path -LiteralPath $DestinationParent)) {
        New-Item -ItemType Directory -Path $DestinationParent -Force | Out-Null
    }

    Copy-Item -LiteralPath $SourcePath -Destination $Destination -Force
    $Hash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
    $Length = (Get-Item -LiteralPath $SourcePath).Length
    [void]$Records.Add([ordered]@{
        relative_path = $RelativePath
        source = $SourcePath
        backup = $Destination
        sha256 = $Hash
        length = $Length
    })
}

function Save-ChapterBackup {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookRoot,

        [Parameter(Mandatory=$true)]
        [string]$ChapterRoot,

        [Parameter(Mandatory=$true)]
        [array]$Items,

        [Parameter(Mandatory=$true)]
        [string]$RunStamp
    )

    $BackupRoot = Join-Path $ChapterRoot ("back\04c44_revision_{0}" -f $RunStamp)
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

    $Records = [System.Collections.ArrayList]::new()
    foreach ($Item in $Items) {
        $SourcePath = Join-Path $ChapterRoot ([string]$Item.file)
        if (!(Test-Path -LiteralPath $SourcePath)) {
            continue
        }

        Add-BackupFile `
            -SourcePath $SourcePath `
            -BackupRoot $BackupRoot `
            -RelativePath ([string]$Item.file) `
            -Records $Records
    }

    $ManifestPath = Join-Path $BackupRoot "backup_manifest.json"
    $Manifest = [ordered]@{
        created_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        purpose = "Chapter backup before 04C44 revision executor."
        book_root = $BookRoot
        backup_root = $BackupRoot
        file_count = $Records.Count
        files = @($Records)
    }
    Save-Utf8File -Path $ManifestPath -Content ($Manifest | ConvertTo-Json -Depth 20)

    return @{
        root = $BackupRoot
        manifest = $ManifestPath
        file_count = $Records.Count
    }
}

function Select-PlanItems {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Items,

        [int]$Chapter,

        [int]$StartChapter,

        [int]$EndChapter
    )

    if ($Chapter -and ($StartChapter -or $EndChapter)) {
        throw "Cannot use -Chapter together with -StartChapter/-EndChapter."
    }

    if ($Chapter) {
        return @($Items | Where-Object { [int]$_.chapter_index -eq $Chapter })
    }

    if ($StartChapter -or $EndChapter) {
        if (-not $StartChapter -or -not $EndChapter) {
            throw "Both -StartChapter and -EndChapter must be specified."
        }
        if ($StartChapter -gt $EndChapter) {
            throw "Invalid range: $StartChapter-$EndChapter"
        }
        return @($Items | Where-Object { [int]$_.chapter_index -ge $StartChapter -and [int]$_.chapter_index -le $EndChapter })
    }

    return @($Items)
}

function Get-ValidationWarnings {
    param(
        [Parameter(Mandatory=$true)]
        $Item,

        [Parameter(Mandatory=$true)]
        [string]$OriginalContent,

        [Parameter(Mandatory=$true)]
        [string]$RevisedContent
    )

    $Warnings = @()
    $OriginalMetrics = Get-TextMetrics -Content $OriginalContent
    $RevisedMetrics = Get-TextMetrics -Content $RevisedContent

    if ([int]$RevisedMetrics.cjk_chars -lt 900) {
        $Warnings += "revised text may be too short"
    }
    if ([int]$RevisedMetrics.headings -lt 1) {
        $Warnings += "no markdown section heading detected"
    }
    if ($RevisedContent -match "`0") {
        $Warnings += "NUL character detected"
    }
    if ([int]$Item.target_cjk_max -gt 0 -and [int]$RevisedMetrics.cjk_chars -gt ([int]$Item.target_cjk_max + 250)) {
        $Warnings += "revised cjk chars exceed target range"
    }
    if ([string]$Item.primary_action -eq "compress" -and [int]$RevisedMetrics.cjk_chars -ge [int]$OriginalMetrics.cjk_chars) {
        $Warnings += "compress action did not reduce cjk chars"
    }
    if ([string]$Item.primary_action -eq "rewrite_opening" -and [int]$RevisedMetrics.cjk_chars -gt ([int]$OriginalMetrics.cjk_chars + 300)) {
        $Warnings += "opening rewrite expanded the section"
    }

    return @{
        warnings = @($Warnings)
        original_metrics = $OriginalMetrics
        revised_metrics = $RevisedMetrics
    }
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
        [hashtable]$Manifest
    )

    $Lines = [System.Collections.ArrayList]::new()
    [void]$Lines.Add("# 04C44 修订执行报告")
    [void]$Lines.Add("")
    [void]$Lines.Add("生成时间：$($Manifest.generated_at)")
    [void]$Lines.Add("")
    [void]$Lines.Add("书名：$($Manifest.book_name)")
    [void]$Lines.Add("")
    [void]$Lines.Add("执行范围：$($Manifest.scope.start_chapter)-$($Manifest.scope.end_chapter)，共 $($Manifest.scope.item_count) 个写作单元")
    [void]$Lines.Add("")
    [void]$Lines.Add("模式：$(if ($Manifest.dry_run) { 'DryRun，仅预演' } else { '正式修订' })")
    [void]$Lines.Add("")
    [void]$Lines.Add("备份目录：$($Manifest.backup.root)")
    [void]$Lines.Add("")
    [void]$Lines.Add("## 结果概览")
    [void]$Lines.Add("")
    if ($Manifest.summary -is [System.Collections.IDictionary]) {
        foreach ($Key in $Manifest.summary.Keys) {
            [void]$Lines.Add("- $Key：$($Manifest.summary[$Key])")
        }
    }
    else {
        foreach ($Property in $Manifest.summary.PSObject.Properties) {
            [void]$Lines.Add("- $($Property.Name)：$($Property.Value)")
        }
    }
    [void]$Lines.Add("")
    [void]$Lines.Add("## 逐节记录")
    [void]$Lines.Add("")
    [void]$Lines.Add("| 编号 | 文件 | 动作 | 状态 | 原字数 | 新字数 | 警告 |")
    [void]$Lines.Add("|---:|---|---|---|---:|---:|---|")
    foreach ($Record in $Manifest.records) {
        $Warnings = if ($Record.warnings) { ($Record.warnings -join "；") } else { "" }
        [void]$Lines.Add("| $($Record.chapter_index) | $($Record.file) | $($Record.primary_action) | $($Record.status) | $($Record.original_cjk_chars) | $($Record.revised_cjk_chars) | $(Escape-MarkdownCell $Warnings) |")
    }

    return ($Lines -join "`r`n")
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context

$BookRoot = $Context.BookRoot
$ChapterRoot = Join-Path $BookRoot "02_chapters"
$BriefRoot = Join-Path $BookRoot "00_brief"

if ([string]::IsNullOrWhiteSpace($PlanPath)) {
    $PlanPath = Join-Path $BriefRoot ("{0}_revision_actions.json" -f $ScopeName)
}

$PlanPath = Resolve-ExistingPath -Path $PlanPath
if (!(Test-Path -LiteralPath $ChapterRoot)) {
    throw "chapter root not found: $ChapterRoot"
}
if (-not $DryRun -and -not $env:OPENAI_API_KEY) {
    throw "OPENAI_API_KEY not set. Use -DryRun for local validation without AI calls."
}

$Plan = Read-Utf8File -Path $PlanPath | ConvertFrom-Json
$Items = @($Plan.items | Sort-Object { [int]$_.chapter_index })
$SelectedItems = Select-PlanItems -Items $Items -Chapter $Chapter -StartChapter $StartChapter -EndChapter $EndChapter

if ($SelectedItems.Count -eq 0) {
    throw "No revision plan items selected."
}

$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$RunRoot = Join-Path $BookRoot ("logs\editorial_loop\{0}_04c44_revision_executor" -f $RunStamp)
$PromptRoot = Join-Path $RunRoot "prompts"
$RawRoot = Join-Path $RunRoot "raw_outputs"
$RevisedRoot = Join-Path $RunRoot "revised_snapshots"
New-Item -ItemType Directory -Path $RunRoot, $PromptRoot, $RawRoot, $RevisedRoot -Force | Out-Null

$Backup = if ($DryRun) {
    @{
        root = ""
        manifest = ""
        file_count = 0
    }
}
else {
    Save-ChapterBackup -BookRoot $BookRoot -ChapterRoot $ChapterRoot -Items $SelectedItems -RunStamp $RunStamp
}

$Records = @()
$Summary = [ordered]@{
    selected = [int]$SelectedItems.Count
    skipped_no_change = 0
    dry_run_planned = 0
    revised = 0
    failed = 0
    warnings = 0
    input_tokens = 0
    output_tokens = 0
    total_tokens = 0
}

foreach ($Item in $SelectedItems) {
    $Index = [int]$Item.chapter_index
    $FileName = [string]$Item.file
    $Action = [string]$Item.primary_action
    $ChapterPath = Join-Path $ChapterRoot $FileName
    $PromptPath = Join-Path $PromptRoot ("{0:D2}_{1}_prompt.md" -f $Index, $Action)
    $RawPath = Join-Path $RawRoot ("{0:D2}_{1}_raw.md" -f $Index, $Action)
    $RevisedSnapshotPath = Join-Path $RevisedRoot $FileName

    Write-Output ("[04C44] {0:D2}: {1} ({2})" -f $Index, $FileName, $Action)

    if (!(Test-Path -LiteralPath $ChapterPath)) {
        $Summary.failed++
        $Records += [ordered]@{
            chapter_index = $Index
            file = $FileName
            primary_action = $Action
            status = "failed"
            error = "chapter file not found"
            original_cjk_chars = 0
            revised_cjk_chars = 0
            warnings = @()
        }
        continue
    }

    $OriginalContent = Read-Utf8File -Path $ChapterPath
    $OriginalMetrics = Get-TextMetrics -Content $OriginalContent

    if ($Action -eq "no_change") {
        $Summary.skipped_no_change++
        $Records += [ordered]@{
            chapter_index = $Index
            file = $FileName
            primary_action = $Action
            status = "skipped_no_change"
            original_cjk_chars = [int]$OriginalMetrics.cjk_chars
            revised_cjk_chars = [int]$OriginalMetrics.cjk_chars
            warnings = @()
        }
        continue
    }

    $Prompt = New-RevisionPrompt -BookName $BookName -Item $Item -OriginalContent (Limit-Text -Text $OriginalContent -MaxChars $MaxExistingChars)
    Save-Utf8File -Path $PromptPath -Content $Prompt

    if ($DryRun) {
        $Summary.dry_run_planned++
        $Records += [ordered]@{
            chapter_index = $Index
            file = $FileName
            primary_action = $Action
            priority = [string]$Item.priority
            status = "dry_run_planned"
            original_cjk_chars = [int]$OriginalMetrics.cjk_chars
            revised_cjk_chars = [int]$OriginalMetrics.cjk_chars
            prompt = $PromptPath
            warnings = @()
        }
        continue
    }

    try {
        $Result = Invoke-SageTextGeneration -Prompt $Prompt -ModelName $Model -OutputTokenLimit $MaxTokens
        $Summary.input_tokens += [int]$Result.usage.input_tokens
        $Summary.output_tokens += [int]$Result.usage.output_tokens
        $Summary.total_tokens += [int]$Result.usage.total_tokens

        Save-Utf8File -Path $RawPath -Content $Result.content

        $RevisedContent = Merge-RevisedBody -OriginalContent $OriginalContent -AiContent $Result.content -Item $Item -ModelName $Model -RunStamp $RunStamp
        $Validation = Get-ValidationWarnings -Item $Item -OriginalContent $OriginalContent -RevisedContent $RevisedContent
        if ($Validation.warnings.Count -gt 0) {
            $Summary.warnings += $Validation.warnings.Count
        }

        Save-Utf8File -Path $ChapterPath -Content $RevisedContent
        Save-Utf8File -Path $RevisedSnapshotPath -Content $RevisedContent

        $Summary.revised++
        $Records += [ordered]@{
            chapter_index = $Index
            file = $FileName
            title = [string]$Item.title
            primary_action = $Action
            secondary_actions = @(To-StringArray -Value $Item.secondary_actions)
            priority = [string]$Item.priority
            status = "revised"
            original_cjk_chars = [int]$Validation.original_metrics.cjk_chars
            revised_cjk_chars = [int]$Validation.revised_metrics.cjk_chars
            original_risk_phrase_count = [int]$Validation.original_metrics.risk_phrase_count
            revised_risk_phrase_count = [int]$Validation.revised_metrics.risk_phrase_count
            prompt = $PromptPath
            raw_output = $RawPath
            revised_snapshot = $RevisedSnapshotPath
            warnings = @($Validation.warnings)
            usage = $Result.usage
        }
    }
    catch {
        $Summary.failed++
        $Records += [ordered]@{
            chapter_index = $Index
            file = $FileName
            title = [string]$Item.title
            primary_action = $Action
            priority = [string]$Item.priority
            status = "failed"
            error = $_.Exception.Message
            original_cjk_chars = [int]$OriginalMetrics.cjk_chars
            revised_cjk_chars = 0
            prompt = $PromptPath
            warnings = @()
        }
    }
}

$StartIndex = ($SelectedItems | Sort-Object { [int]$_.chapter_index } | Select-Object -First 1).chapter_index
$EndIndex = ($SelectedItems | Sort-Object { [int]$_.chapter_index } | Select-Object -Last 1).chapter_index

$Manifest = [ordered]@{
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    generated_by = "04c44-revision-executor.ps1"
    book_name = $BookName
    model = if ($DryRun) { "dry_run_no_ai" } else { $Model }
    dry_run = [bool]$DryRun
    scope = [ordered]@{
        name = $ScopeName
        start_chapter = [int]$StartIndex
        end_chapter = [int]$EndIndex
        item_count = [int]$SelectedItems.Count
    }
    source_paths = [ordered]@{
        book_root = $BookRoot
        chapter_root = $ChapterRoot
        plan = $PlanPath
    }
    backup = $Backup
    summary = $Summary
    records = @($Records)
}

$ManifestPath = Join-Path $RunRoot "manifest.json"
Save-Utf8File -Path $ManifestPath -Content ($Manifest | ConvertTo-Json -Depth 30)

$StableManifestPath = Join-Path $BriefRoot ("{0}_04c44_latest_execution.json" -f $ScopeName)
Save-Utf8File -Path $StableManifestPath -Content ($Manifest | ConvertTo-Json -Depth 30)

$Report = New-MarkdownReport -Manifest $Manifest
$ReportPath = Join-Path $RunRoot "revision_report.md"
$StableReportPath = Join-Path $BriefRoot ("{0}_04c44_revision_report.md" -f $ScopeName)
Save-Utf8File -Path $ReportPath -Content $Report
Save-Utf8File -Path $StableReportPath -Content $Report

$LatestPath = Join-Path $Context.LogRoot "editorial_loop\latest_04c44_revision_executor.json"
Save-Utf8File -Path $LatestPath -Content ($Manifest | ConvertTo-Json -Depth 30)

if ($Summary.failed -gt 0) {
    Write-Output "ERROR: 04C44 completed with failures."
    Write-Output "Manifest: $ManifestPath"
    Write-Output "Report: $ReportPath"
    exit 1
}

Write-Output "SUCCESS: 04C44 revision executor completed."
Write-Output "Manifest: $ManifestPath"
Write-Output "Report: $ReportPath"
Write-Output "Stable report: $StableReportPath"
if (-not $DryRun) {
    Write-Output "Backup: $($Backup.root)"
}
