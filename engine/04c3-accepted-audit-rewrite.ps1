param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Model = "",

    [string]$TocModel,

    [int]$Chapter,

    [int]$StartChapter,

    [int]$EndChapter,

    [int]$MaxTokens = 7000,

    [int]$TocMaxTokens = 32000,

    [int]$MaxExistingChars = 30000,

    [string]$RevisionPlanPath,

    [string]$ExternalBriefPath,

    [string]$MasterReportPath,

    [string]$AdditionalInstructions,

    [switch]$ReferenceGlossary,

    [switch]$SkipTocPreparation,

    [switch]$ForceTocPreparation,

    [switch]$PrepareOnly,

    [switch]$DryRun
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($TocModel)) {
    $TocModel = $Model
}

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

    $Resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    return [System.IO.Path]::GetFullPath($Resolved.Path)
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

function Get-ExistingSectionTitle {
    param([string]$Content)

    $Title = Get-FrontMatterValue -Content $Content -Key "title"
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        return $Title
    }

    $Heading = [regex]::Match($Content -replace "`r", "", "(?m)^###\s+(.+)$")
    if ($Heading.Success) {
        return $Heading.Groups[1].Value.Trim()
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
            Title = $Matches[$i - 1].Groups[1].Value.Trim()
            FileName = $FileName
            Path = Join-Path $ChapterRoot $FileName
        }
    }

    return $Sections
}

function Get-LatestThirdPartyArtifacts {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Context,

        [string]$RevisionPlanPath,

        [string]$ExternalBriefPath,

        [string]$MasterReportPath
    )

    $LatestPath = Join-Path $Context.LogRoot "editorial_loop\latest_third_party.json"
    $Latest = $null
    if (Test-Path -LiteralPath $LatestPath) {
        $Latest = Get-Content -LiteralPath $LatestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $ResolvedRevisionPlanPath = $RevisionPlanPath
    $ResolvedExternalBriefPath = $ExternalBriefPath
    $ResolvedMasterReportPath = $MasterReportPath

    if ([string]::IsNullOrWhiteSpace($ResolvedRevisionPlanPath) -and $Latest -and $Latest.revision_plan) {
        $ResolvedRevisionPlanPath = [string]$Latest.revision_plan
    }
    if ([string]::IsNullOrWhiteSpace($ResolvedRevisionPlanPath) -and $Latest -and $Latest.exported_revision_plan) {
        $ResolvedRevisionPlanPath = [string]$Latest.exported_revision_plan
    }
    if ([string]::IsNullOrWhiteSpace($ResolvedExternalBriefPath) -and $Latest -and $Latest.external_editorial_brief) {
        $ResolvedExternalBriefPath = [string]$Latest.external_editorial_brief
    }
    if ([string]::IsNullOrWhiteSpace($ResolvedMasterReportPath) -and $Latest -and $Latest.current_master_report) {
        $ResolvedMasterReportPath = [string]$Latest.current_master_report
    }
    if ([string]::IsNullOrWhiteSpace($ResolvedMasterReportPath) -and $Latest -and $Latest.master_report) {
        $ResolvedMasterReportPath = [string]$Latest.master_report
    }

    if ([string]::IsNullOrWhiteSpace($ResolvedRevisionPlanPath)) {
        throw "No third-party revision plan found. Run 04c2-third-party-audit.ps1 first, or pass -RevisionPlanPath."
    }

    $ResolvedRevisionPlanPath = Resolve-ExistingPath -Path $ResolvedRevisionPlanPath

    if (-not [string]::IsNullOrWhiteSpace($ResolvedExternalBriefPath)) {
        $ResolvedExternalBriefPath = Resolve-ExistingPath -Path $ResolvedExternalBriefPath
    }
    if (-not [string]::IsNullOrWhiteSpace($ResolvedMasterReportPath)) {
        $ResolvedMasterReportPath = Resolve-ExistingPath -Path $ResolvedMasterReportPath
    }

    return @{
        latest_path = $LatestPath
        revision_plan = $ResolvedRevisionPlanPath
        external_brief = $ResolvedExternalBriefPath
        master_report = $ResolvedMasterReportPath
    }
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

    return $Text.Substring(0, $MaxChars) + "`r`n`r`n[Truncated by 04c3 to keep one-section rewrite prompt within limits.]"
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

function Save-PreRewriteBackup {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookRoot,

        [Parameter(Mandatory=$true)]
        [string]$RunStamp
    )

    $BackupRoot = Join-Path $BookRoot ("backups\accepted_audit_before_rewrite_{0}" -f $RunStamp)
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

    $Records = [System.Collections.ArrayList]::new()
    $RecursiveRoots = @("00_brief", "01_outline", "04_glossary", "04_output")
    foreach ($RelativeRoot in $RecursiveRoots) {
        $SourceRoot = Join-Path $BookRoot $RelativeRoot
        if (!(Test-Path -LiteralPath $SourceRoot)) {
            continue
        }

        Get-ChildItem -LiteralPath $SourceRoot -Recurse -File |
            Where-Object {
                $_.FullName -notmatch "\\back\\" -and
                $_.FullName -notmatch "\\backups\\" -and
                $_.Name -notmatch '^~\$'
            } |
            ForEach-Object {
                $RelativePath = $_.FullName.Substring($BookRoot.Length).TrimStart("\")
                Add-BackupFile -SourcePath $_.FullName -BackupRoot $BackupRoot -RelativePath $RelativePath -Records $Records
            }
    }

    $ChapterRoot = Join-Path $BookRoot "02_chapters"
    if (Test-Path -LiteralPath $ChapterRoot) {
        Get-ChildItem -LiteralPath $ChapterRoot -Filter "*.md" -File |
            Where-Object { $_.Name -notmatch "^_" } |
            Sort-Object Name |
            ForEach-Object {
                $RelativePath = $_.FullName.Substring($BookRoot.Length).TrimStart("\")
                Add-BackupFile -SourcePath $_.FullName -BackupRoot $BackupRoot -RelativePath $RelativePath -Records $Records
            }
    }

    $ManifestPath = Join-Path $BackupRoot "backup_manifest.json"
    $Manifest = [ordered]@{
        created_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        purpose = "Full snapshot before accepted third-party audit TOC preparation and chapter rewrite."
        book_root = $BookRoot
        backup_root = $BackupRoot
        file_count = $Records.Count
        files = @($Records)
    }
    $Manifest | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $ManifestPath -Encoding utf8

    return @{
        root = $BackupRoot
        manifest = $ManifestPath
        file_count = $Records.Count
    }
}

function Get-PreparationState {
    param(
        [Parameter(Mandatory=$true)]
        [string]$StatePath
    )

    if (!(Test-Path -LiteralPath $StatePath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function New-AcceptedAuditTocPrompt {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookTitle,

        [Parameter(Mandatory=$true)]
        [string]$ObjectiveContent,

        [Parameter(Mandatory=$true)]
        [string]$OriginalTocContent,

        [Parameter(Mandatory=$true)]
        [string]$RevisionPlanContent,

        [string]$ExternalBriefContent,

        [string]$MasterReportContent
    )

    $Text = @"
你是 SageWrite 的出版级目录重组编辑。

任务：作者已经全盘接受第三方责任编辑审计报告。请在不写正文的前提下，把旧的 toc.md 重组为一个新的、03-write.ps1 可以直接使用的 toc.md。

书名：
$BookTitle

硬性目标：
1. 全书从约32万字压缩到18万-22万字。
2. 保留 LTC 的核心IP：Learn、Tech、Create。
3. 保留 L 部分的 MCAR + GOAL，T 部分的 DIGIT。
4. C 部分必须明显收束：COCVI 与创造五观作为同一核心模型的理论名称和中文教学表达。
5. C 部分建议重组为第13章到第20章：C总论、Cost、Outcome、Collaboration、Value、Implementation、表达/原型/传播/影响、LTC闭环终章。
6. 减少三级标题和讲义感。每个写作小节下面只保留2-3条真正有用的写作要点。
7. 第一章开头要能引入 AI 时代具体场景和三个核心问题。
8. 加入正式部首：第一部 Learn、第二部 Tech、第三部 Create。
9. 增加参考文献、术语表、模型来源与原创性说明、图示要求等出版组件的目录位置或写作要求。

03兼容格式要求：
1. 必须输出完整 toc.md，不要解释你的修改过程。
2. 文件开头必须保留 YAML front matter。
3. 03-write.ps1 的实际写作单位是以 ### 开头的标题行。
4. ## 用于大章；### 用于实际写作小节。
5. 建议全书 ### 写作小节控制在90-110个之间。
6. 每个 ### 小节必须写明 本节目标字数，建议1,600-2,100字。
7. 每个 ### 小节必须写明 所属大章 和 本节写作要求。
8. 每个 ### 小节末尾保留学术支撑要求，但不得要求虚构文献。
9. 不要使用 Markdown 代码围栏。
10. 输出内容只能是新的 toc.md。

书稿定义 objective.md：
$ObjectiveContent

第三方退修计划：
$RevisionPlanContent

外部编辑审计简报：
$ExternalBriefContent

总编辑审计报告：
$MasterReportContent

旧 toc.md：
$OriginalTocContent
"@

    return $Text
}

function Test-GeneratedToc {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TocContent
    )

    $SectionCount = [regex]::Matches($TocContent, "^###\s+(.+)", "Multiline").Count
    $ChapterCount = [regex]::Matches($TocContent, "^##\s+第.+?章", "Multiline").Count

    if (-not $TocContent.TrimStart().StartsWith("---")) {
        throw "Generated TOC does not start with YAML front matter."
    }
    if ($TocContent -notmatch "(?m)^#\s+写作总规范") {
        throw "Generated TOC is missing 写作总规范."
    }
    if ($SectionCount -lt 90) {
        throw "Generated TOC has too few ### writing sections: $SectionCount. Expected 90-110 for the accepted publication plan."
    }
    if ($SectionCount -gt 115) {
        throw "Generated TOC still has too many ### writing sections: $SectionCount. Expected 90-110."
    }
    if ($ChapterCount -lt 16) {
        throw "Generated TOC has too few major chapters: $ChapterCount."
    }
    if ($TocContent -notmatch "参考文献" -or $TocContent -notmatch "术语表" -or $TocContent -notmatch "原创") {
        throw "Generated TOC is missing required publication components: references, terminology table, or originality/source statement."
    }

    $Tail = $TocContent.Substring([Math]::Max(0, $TocContent.Length - 500))
    if ($Tail -notmatch "不得虚构文献|参考文献|术语表|原创|索引|结语") {
        throw "Generated TOC tail does not look complete; output may have been truncated."
    }

    return @{
        section_count = $SectionCount
        chapter_count = $ChapterCount
    }
}

function Convert-TocPreparationForManifest {
    param(
        [Parameter(Mandatory=$true)]
        $TocPreparation
    )

    $Result = [ordered]@{}
    $Pairs = @()
    if ($TocPreparation -is [System.Collections.IDictionary]) {
        foreach ($Key in $TocPreparation.Keys) {
            $Pairs += [pscustomobject]@{
                Key = [string]$Key
                Value = $TocPreparation[$Key]
            }
        }
    }
    elseif ($TocPreparation -is [pscustomobject] -or $TocPreparation.GetType().Name -eq "PSCustomObject") {
        foreach ($Property in $TocPreparation.PSObject.Properties) {
            $Pairs += [pscustomobject]@{
                Key = [string]$Property.Name
                Value = $Property.Value
            }
        }
    }
    else {
        return [ordered]@{
            status = "unknown"
            note = "Unable to summarize TOC preparation object."
        }
    }

    foreach ($Pair in $Pairs) {
        $Key = $Pair.Key
        $Value = $Pair.Value
        if ($Key -eq "toc_content") {
            $Content = [string]$Value
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
            $Sha = [System.Security.Cryptography.SHA256]::Create()
            $HashBytes = $Sha.ComputeHash($Bytes)
            $Hash = ([System.BitConverter]::ToString($HashBytes)).Replace("-", "")
            $Result["toc_content_length"] = $Content.Length
            $Result["toc_content_sha256"] = $Hash
            continue
        }

        $Result[$Key] = $Value
    }

    return $Result
}

function Invoke-TocPreparation {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Context,

        [Parameter(Mandatory=$true)]
        [string]$BookTitle,

        [Parameter(Mandatory=$true)]
        [string]$BookRoot,

        [Parameter(Mandatory=$true)]
        [string]$TocPath,

        [Parameter(Mandatory=$true)]
        [string]$OriginalTocContent,

        [Parameter(Mandatory=$true)]
        [string]$ObjectiveContent,

        [Parameter(Mandatory=$true)]
        [string]$RevisionPlanContent,

        [string]$ExternalBriefContent,

        [string]$MasterReportContent,

        [Parameter(Mandatory=$true)]
        [string]$RunRoot,

        [Parameter(Mandatory=$true)]
        [string]$RunStamp,

        [Parameter(Mandatory=$true)]
        [string]$ModelName,

        [Parameter(Mandatory=$true)]
        [int]$OutputTokenLimit,

        [switch]$DryRun,

        [switch]$Skip,

        [switch]$Force
    )

    $StatePath = Join-Path $BookRoot "00_brief\accepted_audit_rewrite_state.json"
    $ExistingState = Get-PreparationState -StatePath $StatePath
    $OriginalStats = @{
        section_count = [regex]::Matches($OriginalTocContent, "^###\s+(.+)", "Multiline").Count
        chapter_count = [regex]::Matches($OriginalTocContent, "^##\s+第.+?章", "Multiline").Count
    }

    if ($Skip) {
        return @{
            status = "skipped_by_user"
            state_path = $StatePath
            backup_root = ""
            prompt_path = ""
            candidate_path = ""
            original_stats = $OriginalStats
            new_stats = $OriginalStats
            toc_content = $OriginalTocContent
        }
    }

    if ($ExistingState -and $ExistingState.toc_prepared -and (-not $Force)) {
        return @{
            status = "already_prepared"
            state_path = $StatePath
            backup_root = [string]$ExistingState.backup_root
            prompt_path = [string]$ExistingState.prompt_path
            candidate_path = [string]$ExistingState.candidate_path
            original_stats = $OriginalStats
            new_stats = @{
                section_count = $ExistingState.new_section_count
                chapter_count = $ExistingState.new_chapter_count
            }
            toc_content = $OriginalTocContent
        }
    }

    $MasterReportForPrompt = Limit-Text -Text $MasterReportContent -MaxChars 50000
    $Prompt = New-AcceptedAuditTocPrompt `
        -BookTitle $BookTitle `
        -ObjectiveContent $ObjectiveContent `
        -OriginalTocContent $OriginalTocContent `
        -RevisionPlanContent $RevisionPlanContent `
        -ExternalBriefContent $ExternalBriefContent `
        -MasterReportContent $MasterReportForPrompt

    $PromptPath = Join-Path $RunRoot "toc_rewrite_prompt.md"
    Save-Utf8File -Path $PromptPath -Content $Prompt

    if ($DryRun) {
        return @{
            status = "dry_run_prompt_saved"
            state_path = $StatePath
            backup_root = ""
            prompt_path = $PromptPath
            candidate_path = ""
            original_stats = $OriginalStats
            new_stats = $OriginalStats
            toc_content = $OriginalTocContent
        }
    }

    $Backup = Save-PreRewriteBackup -BookRoot $BookRoot -RunStamp $RunStamp
    $TocBeforePath = Join-Path (Split-Path -Parent $TocPath) ("toc.before_accepted_audit_{0}.md" -f $RunStamp)
    Copy-Item -LiteralPath $TocPath -Destination $TocBeforePath -Force

    $Result = Invoke-SageTextGeneration -Prompt $Prompt -ModelName $ModelName -OutputTokenLimit $OutputTokenLimit
    $NewTocContent = Normalize-MarkdownOutput -Content $Result.content
    $CandidatePath = Join-Path $RunRoot "toc.accepted_audit_candidate.md"
    Save-Utf8File -Path $CandidatePath -Content $NewTocContent

    $NewStats = Test-GeneratedToc -TocContent $NewTocContent
    Save-Utf8File -Path $TocPath -Content $NewTocContent

    $RetiredChapterRoot = ""
    if ($NewStats.section_count -lt $OriginalStats.section_count) {
        $ChapterRoot = Join-Path $BookRoot "02_chapters"
        $RetiredChapterRoot = Join-Path $ChapterRoot ("back\accepted_audit_retired_{0}" -f $RunStamp)
        $ResolvedChapterRoot = [System.IO.Path]::GetFullPath($ChapterRoot)
        $ResolvedRetiredRoot = [System.IO.Path]::GetFullPath($RetiredChapterRoot)
        if (-not $ResolvedRetiredRoot.StartsWith($ResolvedChapterRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to archive retired chapters outside 02_chapters."
        }

        New-Item -ItemType Directory -Path $RetiredChapterRoot -Force | Out-Null
        for ($i = ($NewStats.section_count + 1); $i -le $OriginalStats.section_count; $i++) {
            $OldFile = Join-Path $ChapterRoot ("{0:D2}.md" -f $i)
            if (Test-Path -LiteralPath $OldFile) {
                Move-Item -LiteralPath $OldFile -Destination (Join-Path $RetiredChapterRoot ([System.IO.Path]::GetFileName($OldFile))) -Force
            }
        }
    }

    $State = [ordered]@{
        toc_prepared = $true
        prepared_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        run_root = $RunRoot
        state_path = $StatePath
        toc_path = $TocPath
        toc_before_path = $TocBeforePath
        backup_root = $Backup.root
        backup_manifest = $Backup.manifest
        backup_file_count = $Backup.file_count
        retired_chapter_root = $RetiredChapterRoot
        prompt_path = $PromptPath
        candidate_path = $CandidatePath
        model = $ModelName
        original_section_count = $OriginalStats.section_count
        original_chapter_count = $OriginalStats.chapter_count
        new_section_count = $NewStats.section_count
        new_chapter_count = $NewStats.chapter_count
        input_tokens = $Result.usage.input_tokens
        output_tokens = $Result.usage.output_tokens
        total_tokens = $Result.usage.total_tokens
    }
    $State | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $StatePath -Encoding utf8

    return @{
        status = "prepared"
        state_path = $StatePath
        backup_root = $Backup.root
        backup_manifest = $Backup.manifest
        retired_chapter_root = $RetiredChapterRoot
        prompt_path = $PromptPath
        candidate_path = $CandidatePath
        original_stats = $OriginalStats
        new_stats = $NewStats
        toc_content = $NewTocContent
        usage = $Result.usage
    }
}

function New-GlobalRewriteInstructions {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookTitle,

        [Parameter(Mandatory=$true)]
        [string]$RevisionPlanPath,

        [Parameter(Mandatory=$true)]
        [string]$RevisionPlanContent,

        [string]$ExternalBriefPath,

        [string]$ExternalBriefContent,

        [string]$MasterReportPath,

        [string]$AdditionalInstructions
    )

    $ExternalBlock = ""
    if (-not [string]::IsNullOrWhiteSpace($ExternalBriefContent)) {
        $ExternalBlock = @"

## External Editorial Brief

Source:
$ExternalBriefPath

$ExternalBriefContent
"@
    }

    $AdditionalBlock = ""
    if (-not [string]::IsNullOrWhiteSpace($AdditionalInstructions)) {
        $AdditionalBlock = @"

## User Additional Instructions For This Rewrite Batch

$AdditionalInstructions
"@
    }

    $Text = @"
# Accepted Third-Party Editorial Rewrite Instructions

Book:
$BookTitle

Author decision:
The author fully accepts the third-party editorial audit. Treat the third-party audit as accepted editorial direction, not merely optional reference.

Revision plan source:
$RevisionPlanPath

Master report:
$MasterReportPath

Non-negotiable rewrite direction:
1. Move the manuscript toward a formal publication draft, not a longer theory draft.
2. Reduce repetition, excessive definitions, predictable sentence patterns, and classroom-handout texture.
3. Preserve the LTC core IP and the author's original thesis.
4. Strengthen academic credibility by distinguishing existing research, author inference, original model, practice experience, and value judgment.
5. Use steadier scholarly language. Reduce absolute claims where they create avoidable risk.
6. Unify terminology across LTC, MCAR, GOAL, DIGIT, COCVI, and the Chinese model names.
7. Treat COCVI and 创造五观 as one core C-part model unless the TOC explicitly requires otherwise.
8. Prefer fewer, stronger subheadings inside each section. Avoid turning every paragraph into a numbered mini-outline.
9. Add author voice, concrete observation, and reader-facing narrative where the old manuscript feels templated.
10. Do not add new chapters or adjacent sections in this step. Rewrite only the current TOC writing unit.

## Accepted Third-Party Revision Plan

$RevisionPlanContent
$ExternalBlock
$AdditionalBlock
"@

    return $Text
}

function New-SectionRewriteInstructions {
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Section,

        [Parameter(Mandatory=$true)]
        [string]$GlobalInstructions,

        [string]$ExistingContent,

        [int]$MaxExistingChars
    )

    $ExistingBlock = ""
    if (-not [string]::IsNullOrWhiteSpace($ExistingContent)) {
        $LimitedExisting = Limit-Text -Text $ExistingContent -MaxChars $MaxExistingChars
        $ExistingCharCount = $ExistingContent.Length
        $TargetLow = [Math]::Max(900, [int]($ExistingCharCount * 0.65))
        $TargetHigh = [Math]::Max($TargetLow + 200, [int]($ExistingCharCount * 0.80))
        $ExistingBlock = @"

## Existing Section Manuscript To Revise

Existing approximate character count:
$ExistingCharCount

Accepted-audit length target for this rewrite:
Aim for roughly $TargetLow-$TargetHigh Chinese characters including Markdown headings and body text, unless this section genuinely needs extra evidence or a bridging transition. This reduction target is part of the accepted third-party audit and should prevent the manuscript from expanding again.

$LimitedExisting
"@
    }
    else {
        $ExistingBlock = @"

## Accepted-Audit Length Target

No existing section manuscript was found. Write a concise replacement section, normally 1,400-1,800 Chinese characters unless the TOC explicitly requires a different length.
"@
    }

    $Text = @"
$GlobalInstructions

## Current Section Rewrite Task

Writing unit index:
$($Section.Index) / $($Section.Total)

Writing unit title:
$($Section.Title)

Output requirement:
Rewrite this one writing unit as a polished replacement manuscript. Use the existing manuscript as raw material when available, but accept the third-party audit direction fully.

Important boundaries:
1. Write only this current writing unit.
2. Do not write the whole parent chapter.
3. Do not write adjacent TOC sections.
4. Do not include an editor report, revision explanation, or meta commentary.
5. Output clean Markdown manuscript only.
$ExistingBlock
"@

    return $Text
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "accepted_audit_rewrite" -Data @{
    model = $Model
    toc_model = $TocModel
    chapter = $Chapter
    start_chapter = $StartChapter
    end_chapter = $EndChapter
    max_tokens = $MaxTokens
    toc_max_tokens = $TocMaxTokens
    skip_toc_preparation = [bool]$SkipTocPreparation
    force_toc_preparation = [bool]$ForceTocPreparation
    prepare_only = [bool]$PrepareOnly
    has_additional_instructions = (-not [string]::IsNullOrWhiteSpace($AdditionalInstructions))
    dry_run = [bool]$DryRun
}

try {
    $BookRoot = $Context.BookRoot
    $TocPath = Join-Path $BookRoot "01_outline\toc.md"
    $ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
    $ChapterRoot = Join-Path $BookRoot "02_chapters"
    $LoopRoot = Join-Path $Context.LogRoot "editorial_loop"
    $RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $RunRoot = Join-Path $LoopRoot ("{0}_accepted_audit_rewrite" -f $RunStamp)
    $InstructionRoot = Join-Path $RunRoot "instructions"
    $CommandLogRoot = Join-Path $RunRoot "chapter_logs"

    if (!(Test-Path -LiteralPath $TocPath)) {
        throw "toc.md not found: $TocPath"
    }
    if (!(Test-Path -LiteralPath $ObjectivePath)) {
        throw "objective.md not found: $ObjectivePath"
    }
    if (!(Test-Path -LiteralPath $ChapterRoot)) {
        throw "02_chapters folder not found: $ChapterRoot"
    }
    if ($Chapter -and (-not $SkipTocPreparation)) {
        Write-Output "Note: TOC preparation runs before single-section rewrite unless -SkipTocPreparation is used."
    }

    New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $InstructionRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $CommandLogRoot -Force | Out-Null

    $TocContent = Get-Content -LiteralPath $TocPath -Raw -Encoding UTF8
    $ObjectiveContent = Get-Content -LiteralPath $ObjectivePath -Raw -Encoding UTF8
    $BookTitle = Get-FrontMatterValue -Content $ObjectiveContent -Key "title"
    if ([string]::IsNullOrWhiteSpace($BookTitle)) {
        $BookTitle = $BookName
    }

    $Artifacts = Get-LatestThirdPartyArtifacts `
        -Context $Context `
        -RevisionPlanPath $RevisionPlanPath `
        -ExternalBriefPath $ExternalBriefPath `
        -MasterReportPath $MasterReportPath

    $ResolvedRevisionPlanPath = $Artifacts.revision_plan
    $ResolvedExternalBriefPath = $Artifacts.external_brief
    $ResolvedMasterReportPath = $Artifacts.master_report

    $RevisionPlanContent = Read-Utf8File -Path $ResolvedRevisionPlanPath
    $ExternalBriefContent = if (-not [string]::IsNullOrWhiteSpace($ResolvedExternalBriefPath)) {
        Read-Utf8File -Path $ResolvedExternalBriefPath
    }
    else {
        ""
    }
    $MasterReportContent = if (-not [string]::IsNullOrWhiteSpace($ResolvedMasterReportPath) -and (Test-Path -LiteralPath $ResolvedMasterReportPath)) {
        Read-Utf8File -Path $ResolvedMasterReportPath
    }
    else {
        ""
    }

    $TocPreparation = Invoke-TocPreparation `
        -Context $Context `
        -BookTitle $BookTitle `
        -BookRoot $BookRoot `
        -TocPath $TocPath `
        -OriginalTocContent $TocContent `
        -ObjectiveContent $ObjectiveContent `
        -RevisionPlanContent $RevisionPlanContent `
        -ExternalBriefContent $ExternalBriefContent `
        -MasterReportContent $MasterReportContent `
        -RunRoot $RunRoot `
        -RunStamp $RunStamp `
        -ModelName $TocModel `
        -OutputTokenLimit $TocMaxTokens `
        -DryRun:$DryRun `
        -Skip:$SkipTocPreparation `
        -Force:$ForceTocPreparation

    $TocContent = $TocPreparation.toc_content
    $TocPreparationManifest = Convert-TocPreparationForManifest -TocPreparation $TocPreparation
    Write-Output "TOC preparation status: $($TocPreparation.status)"

    if ($PrepareOnly) {
        $ManifestPath = Join-Path $RunRoot "manifest.json"
        $Manifest = [ordered]@{
            generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            book_name = $BookName
            book_title = $BookTitle
            model = $Model
            toc_model = $TocModel
            dry_run = [bool]$DryRun
            prepare_only = $true
            scope = "toc_preparation_only"
            revision_plan = $ResolvedRevisionPlanPath
            external_brief = $ResolvedExternalBriefPath
            master_report = $ResolvedMasterReportPath
            toc_preparation = $TocPreparationManifest
            generated_count = 0
            processed_count = 0
            run_root = $RunRoot
        }
        $Manifest | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $ManifestPath -Encoding utf8

        $LatestAcceptedRewritePath = Join-Path $LoopRoot "latest_accepted_audit_rewrite.json"
        $Manifest | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $LatestAcceptedRewritePath -Encoding utf8

        Complete-SageStep -Context $Context -Step "accepted_audit_rewrite" -State "success" -Message "Accepted audit TOC preparation completed." -Data @{
            dry_run = [bool]$DryRun
            prepare_only = $true
            manifest = $ManifestPath
            toc_preparation_status = $TocPreparation.status
            backup_root = $TocPreparation.backup_root
        }

        Write-Output "SUCCESS: Accepted audit TOC preparation completed."
        Write-Output "Run folder: $RunRoot"
        Write-Output "Manifest: $ManifestPath"
        if ($DryRun) {
            Write-Output "Dry run only. TOC prompt saved, but toc.md was not changed."
        }
        return
    }

    $Sections = @(Get-ScopedTocSections -TocContent $TocContent -ChapterRoot $ChapterRoot -Chapter $Chapter -StartChapter $StartChapter -EndChapter $EndChapter)
    $ScopeText = "writing_units=$($Sections.Count); range=$($Sections[0].Index)-$($Sections[$Sections.Count - 1].Index); files=" + (($Sections | Select-Object -ExpandProperty FileName) -join ", ")

    $GlobalInstructions = New-GlobalRewriteInstructions `
        -BookTitle $BookTitle `
        -RevisionPlanPath $ResolvedRevisionPlanPath `
        -RevisionPlanContent $RevisionPlanContent `
        -ExternalBriefPath $ResolvedExternalBriefPath `
        -ExternalBriefContent $ExternalBriefContent `
        -MasterReportPath $ResolvedMasterReportPath `
        -AdditionalInstructions $AdditionalInstructions

    $GlobalInstructionPath = Join-Path $RunRoot "accepted_audit_global_instructions.md"
    Save-Utf8File -Path $GlobalInstructionPath -Content $GlobalInstructions

    $BackupRoot = ""
    if (-not $DryRun) {
        $BackupRoot = Join-Path $ChapterRoot ("back\accepted_audit_rewrite_{0}" -f $RunStamp)
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
        foreach ($Section in $Sections) {
            if (Test-Path -LiteralPath $Section.Path) {
                Copy-Item -LiteralPath $Section.Path -Destination (Join-Path $BackupRoot $Section.FileName) -Force
            }
        }
    }

    $WriteScript = Join-Path $Context.EnginePath "03-write.ps1"
    $Processed = @()
    $GeneratedCount = 0
    $StartTime = Get-Date

    foreach ($Section in $Sections) {
        Write-Output "[accepted-audit] $($Section.Index) / $($Section.Total): $($Section.Title)"

        $ExistingContent = if (Test-Path -LiteralPath $Section.Path) {
            Get-Content -LiteralPath $Section.Path -Raw -Encoding UTF8
        }
        else {
            ""
        }
        $ExistingContentForInstructions = $ExistingContent
        $ExistingTitle = ""
        if (-not [string]::IsNullOrWhiteSpace($ExistingContent)) {
            $ExistingTitle = Get-ExistingSectionTitle -Content $ExistingContent
            if (-not [string]::IsNullOrWhiteSpace($ExistingTitle)) {
                $ExistingTitleKey = Normalize-ComparableTitle -Title $ExistingTitle
                $CurrentTitleKey = Normalize-ComparableTitle -Title $Section.Title
                if ($ExistingTitleKey -ne $CurrentTitleKey) {
                    Write-Output ("[accepted-audit] existing title mismatch for {0}: '{1}' -> '{2}'. Existing manuscript will be ignored for rewrite prompt." -f $Section.FileName, $ExistingTitle, $Section.Title)
                    $ExistingContentForInstructions = ""
                }
            }
        }

        $SectionInstructions = New-SectionRewriteInstructions `
            -Section $Section `
            -GlobalInstructions $GlobalInstructions `
            -ExistingContent $ExistingContentForInstructions `
            -MaxExistingChars $MaxExistingChars

        $SectionInstructionPath = Join-Path $InstructionRoot ("{0:D2}_instructions.md" -f $Section.Index)
        Save-Utf8File -Path $SectionInstructionPath -Content $SectionInstructions

        $ChapterRecord = [ordered]@{
            index = $Section.Index
            title = $Section.Title
            file = $Section.Path
            instruction = $SectionInstructionPath
            existing_title = $ExistingTitle
            existing_content_used = (-not [string]::IsNullOrWhiteSpace($ExistingContentForInstructions))
            status = "dry_run"
        }

        if ($DryRun) {
            Write-Output "Dry run: would call 03-write.ps1 -Chapter $($Section.Index) -Force"
        }
        else {
            $LogPath = Join-Path $CommandLogRoot ("{0:D2}_03-write.log" -f $Section.Index)
            if ($ReferenceGlossary) {
                $CommandOutput = & $WriteScript `
                    -BookName $BookName `
                    -Model $Model `
                    -Chapter $Section.Index `
                    -MaxTokens $MaxTokens `
                    -AdditionalInstructions $SectionInstructions `
                    -ReferenceGlossary `
                    -Force 2>&1
            }
            else {
                $CommandOutput = & $WriteScript `
                    -BookName $BookName `
                    -Model $Model `
                    -Chapter $Section.Index `
                    -MaxTokens $MaxTokens `
                    -AdditionalInstructions $SectionInstructions `
                    -Force 2>&1
            }
            $CommandOutput | Out-File -LiteralPath $LogPath -Encoding utf8
            $ChapterRecord.status = "generated"
            $ChapterRecord.log = $LogPath
            $GeneratedCount++
        }

        $Processed += [pscustomobject]$ChapterRecord
    }

    $Duration = ((Get-Date) - $StartTime).TotalSeconds

    $ManifestPath = Join-Path $RunRoot "manifest.json"
    $Manifest = [ordered]@{
        generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        book_name = $BookName
        book_title = $BookTitle
        model = $Model
        toc_model = $TocModel
        dry_run = [bool]$DryRun
        prepare_only = $false
        scope = $ScopeText
        revision_plan = $ResolvedRevisionPlanPath
        external_brief = $ResolvedExternalBriefPath
        master_report = $ResolvedMasterReportPath
        toc_preparation = $TocPreparationManifest
        global_instructions = $GlobalInstructionPath
        backup_root = $BackupRoot
        chapter_backup_root = $BackupRoot
        max_tokens = $MaxTokens
        toc_max_tokens = $TocMaxTokens
        max_existing_chars = $MaxExistingChars
        additional_instructions = $AdditionalInstructions
        reference_glossary = [bool]$ReferenceGlossary
        generated_count = $GeneratedCount
        processed_count = $Processed.Count
        duration_seconds = [math]::Round($Duration, 2)
        chapters = $Processed
        run_root = $RunRoot
    }
    $Manifest | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $ManifestPath -Encoding utf8

    $LatestAcceptedRewritePath = Join-Path $LoopRoot "latest_accepted_audit_rewrite.json"
    $Manifest | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $LatestAcceptedRewritePath -Encoding utf8

    Complete-SageStep -Context $Context -Step "accepted_audit_rewrite" -State "success" -Message "Accepted audit rewrite completed." -Data @{
        dry_run = [bool]$DryRun
        toc_preparation_status = $TocPreparation.status
        scope = $ScopeText
        manifest = $ManifestPath
        generated_count = $GeneratedCount
        processed_count = $Processed.Count
        chapter_backup_root = $BackupRoot
        toc_backup_root = $TocPreparation.backup_root
    }

    Write-Output "SUCCESS: Accepted audit rewrite completed."
    Write-Output "Run folder: $RunRoot"
    Write-Output "Manifest: $ManifestPath"
    Write-Output "TOC preparation: $($TocPreparation.status)"
    Write-Output "Processed: $($Processed.Count)"
    if ($DryRun) {
        Write-Output "Dry run only. No chapters were rewritten."
    }
    else {
        Write-Output "Generated: $GeneratedCount"
        Write-Output "Backup: $BackupRoot"
    }
}
catch {
    $Message = $_.Exception.Message
    Fail-SageStep -Context $Context -Step "accepted_audit_rewrite" -Message $Message -Data @{
        dry_run = [bool]$DryRun
        chapter = $Chapter
        start_chapter = $StartChapter
        end_chapter = $EndChapter
    }
    Write-Error $Message
    exit 1
}
