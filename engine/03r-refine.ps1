param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [string]$Language,

    [string]$Model = "",

    [int]$Chapter,
    [int]$StartChapter,
    [int]$EndChapter,

    [switch]$All,
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

function Get-LanguageProfile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LanguageCode
    )

    $Normalized = $LanguageCode.Trim().ToLowerInvariant()
    switch ($Normalized) {
        "en"      { return @{ code = "en";      name = "English";             native_name = "English" } }
        "ms"      { return @{ code = "ms";      name = "Malay";               native_name = "Bahasa Melayu" } }
        "fr"      { return @{ code = "fr";      name = "French";              native_name = "Francais" } }
        "de"      { return @{ code = "de";      name = "German";              native_name = "Deutsch" } }
        "es"      { return @{ code = "es";      name = "Spanish";             native_name = "Espanol" } }
        "it"      { return @{ code = "it";      name = "Italian";             native_name = "Italiano" } }
        "pt"      { return @{ code = "pt";      name = "Portuguese";          native_name = "Portugues" } }
        "ja"      { return @{ code = "ja";      name = "Japanese";            native_name = "Japanese" } }
        "ko"      { return @{ code = "ko";      name = "Korean";              native_name = "Korean" } }
        "ru"      { return @{ code = "ru";      name = "Russian";             native_name = "Russian" } }
        "ar"      { return @{ code = "ar";      name = "Arabic";              native_name = "Arabic" } }
        "zh"      { return @{ code = "zh";      name = "Chinese";             native_name = "Chinese" } }
        "zh-cn"   { return @{ code = "zh-cn";   name = "Simplified Chinese";  native_name = "Chinese" } }
        "zh-hans" { return @{ code = "zh-hans"; name = "Simplified Chinese";  native_name = "Chinese" } }
        "zh-tw"   { return @{ code = "zh-tw";   name = "Traditional Chinese"; native_name = "Chinese" } }
        "zh-hant" { return @{ code = "zh-hant"; name = "Traditional Chinese"; native_name = "Chinese" } }
        default   { return @{ code = $Normalized; name = $LanguageCode.Trim(); native_name = $LanguageCode.Trim() } }
    }
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

function Save-Utf8File {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Encoding = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($Path, $Content, $Encoding)
}

function Split-TextSentences {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Normalized = $Content -replace "`r", ""
    if ([string]::IsNullOrWhiteSpace($Normalized)) {
        return @()
    }

    $RawSentences = @()
    $Buffer = New-Object System.Text.StringBuilder

    foreach ($Char in $Normalized.ToCharArray()) {
        [void]$Buffer.Append($Char)

        $CodePoint = [int][char]$Char
        $ShouldBreak = $false

        if ($CodePoint -in @(10, 33, 46, 59, 63, 12290, 65281, 65307, 65311)) {
            $ShouldBreak = $true
        }

        if ($ShouldBreak) {
            $Value = $Buffer.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($Value)) {
                $RawSentences += ,$Value
            }
            [void]$Buffer.Clear()
        }
    }

    if ($Buffer.Length -gt 0) {
        $Value = $Buffer.ToString().Trim()
        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            $RawSentences += ,$Value
        }
    }

    $Sentences = @()
    foreach ($Sentence in $RawSentences) {
        if ($Sentences.Count -gt 0 -and $Sentence -match '^[\)"''\]\}]+$') {
            $Sentences[$Sentences.Count - 1] = $Sentences[$Sentences.Count - 1] + $Sentence
        }
        else {
            $Sentences += ,$Sentence
        }
    }

    return ,$Sentences
}

function Normalize-ComparableSentence {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    return ([regex]::Replace(($Content -replace "`r", "").Trim(), "\s+", " "))
}

function Get-SentenceDiffPoints {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$OriginalSentences,

        [Parameter(Mandatory=$true)]
        [string[]]$RefinedSentences
    )

    $DiffPoints = @()
    $OriginalIndex = 0
    $RefinedIndex = 0

    while ($OriginalIndex -lt $OriginalSentences.Count -or $RefinedIndex -lt $RefinedSentences.Count) {
        $OriginalSentence = if ($OriginalIndex -lt $OriginalSentences.Count) { $OriginalSentences[$OriginalIndex] } else { $null }
        $RefinedSentence = if ($RefinedIndex -lt $RefinedSentences.Count) { $RefinedSentences[$RefinedIndex] } else { $null }

        if ($null -ne $OriginalSentence -and $null -ne $RefinedSentence) {
            if ((Normalize-ComparableSentence -Content $OriginalSentence) -eq (Normalize-ComparableSentence -Content $RefinedSentence)) {
                $OriginalIndex++
                $RefinedIndex++
                continue
            }

            $NextOriginal = if (($OriginalIndex + 1) -lt $OriginalSentences.Count) { $OriginalSentences[$OriginalIndex + 1] } else { $null }
            $NextRefined = if (($RefinedIndex + 1) -lt $RefinedSentences.Count) { $RefinedSentences[$RefinedIndex + 1] } else { $null }

            if ($null -ne $NextOriginal -and (Normalize-ComparableSentence -Content $NextOriginal) -eq (Normalize-ComparableSentence -Content $RefinedSentence)) {
                $DiffPoints += ,([pscustomobject]@{
                    original = $OriginalSentence
                    refined  = ""
                })
                $OriginalIndex++
                continue
            }

            if ($null -ne $NextRefined -and (Normalize-ComparableSentence -Content $OriginalSentence) -eq (Normalize-ComparableSentence -Content $NextRefined)) {
                $DiffPoints += ,([pscustomobject]@{
                    original = ""
                    refined  = $RefinedSentence
                })
                $RefinedIndex++
                continue
            }

            $DiffPoints += ,([pscustomobject]@{
                original = $OriginalSentence
                refined  = $RefinedSentence
            })
            $OriginalIndex++
            $RefinedIndex++
            continue
        }

        if ($null -ne $OriginalSentence) {
            $DiffPoints += ,([pscustomobject]@{
                original = $OriginalSentence
                refined  = ""
            })
            $OriginalIndex++
            continue
        }

        $DiffPoints += ,([pscustomobject]@{
            original = ""
            refined  = $RefinedSentence
        })
        $RefinedIndex++
    }

    return ,$DiffPoints
}

function New-DiffReportContent {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RelativePath,

        [Parameter(Mandatory=$true)]
        [string]$OriginalText,

        [Parameter(Mandatory=$true)]
        [string]$RefinedText
    )

    $OriginalSentences = Split-TextSentences -Content $OriginalText
    $RefinedSentences = Split-TextSentences -Content $RefinedText
    $DiffPoints = Get-SentenceDiffPoints -OriginalSentences $OriginalSentences -RefinedSentences $RefinedSentences

    $ReportLines = New-Object System.Collections.Generic.List[string]
    $ReportLines.Add("# Difference Report")
    $ReportLines.Add("")
    $ReportLines.Add("File: $RelativePath")
    $ReportLines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $ReportLines.Add("")
    $ReportLines.Add("## Sentence-Level Differences")
    $ReportLines.Add("")

    if ($DiffPoints.Count -eq 0) {
        $ReportLines.Add("No sentence-level differences detected.")
    }
    else {
        for ($Index = 0; $Index -lt $DiffPoints.Count; $Index++) {
            $Point = $DiffPoints[$Index]
            $ReportLines.Add("### Difference $($Index + 1)")
            $ReportLines.Add("")
            $ReportLines.Add("Original sentence:")
            $ReportLines.Add("")
            $ReportLines.Add("> " + $(if ([string]::IsNullOrWhiteSpace($Point.original)) { "(none)" } else { $Point.original }))
            $ReportLines.Add("")
            $ReportLines.Add("Refined sentence:")
            $ReportLines.Add("")
            $ReportLines.Add("> " + $(if ([string]::IsNullOrWhiteSpace($Point.refined)) { "(none)" } else { $Point.refined }))
            $ReportLines.Add("")
        }
    }

    $ReportLines.Add("## Summary")
    $ReportLines.Add("")
    $ReportLines.Add("- Original sentence count: $($OriginalSentences.Count)")
    $ReportLines.Add("- Refined sentence count: $($RefinedSentences.Count)")
    $ReportLines.Add("- Total difference points: $($DiffPoints.Count)")
    $ReportLines.Add("- Difference total: $($DiffPoints.Count)")

    return ($ReportLines -join "`r`n")
}

function Get-TextHash {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
        $HashBytes = $Sha.ComputeHash($Bytes)
        return ([System.BitConverter]::ToString($HashBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $Sha.Dispose()
    }
}

function Get-RefineResult {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceText,

        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$ModelName,

        [Parameter(Mandatory=$true)]
        [string]$TargetLanguageName,

        [Parameter(Mandatory=$true)]
        [string]$FileRole,

        [Parameter(Mandatory=$true)]
        [string]$RelativePath
    )

    $Prompt = @"
You are polishing an existing SageWrite markdown file written in $TargetLanguageName.

File role: $FileRole
Relative path: $RelativePath

Your job:
- Refine this file in $TargetLanguageName with the smallest possible number of edits.
- Only fix clear grammar, spelling, punctuation, or clearly incorrect word usage.
- Keep the meaning intact.
- Keep the language in $TargetLanguageName. Do not translate it into another language.

Rules:
1. Preserve valid Markdown structure exactly.
2. Preserve all front matter keys exactly as written.
3. Preserve heading levels, lists, numbering, blockquotes, tables, links, and code fences.
4. Preserve filenames, chapter indexes, dates, numeric ids, and machine-readable metadata.
5. Do not add commentary, explanations, or surrounding code fences.
6. Return only the improved markdown file content.
7. Only make sentence-internal edits. Do not reorder, merge, split, summarize, expand, or restructure paragraphs or sections.
8. If a sentence is already correct and natural, leave it unchanged.
9. Do not do synonym-swapping optimization, stylistic rewriting, or tone polishing for preference.
10. The output should stay as close to the source text as possible.
11. If the whole file does not clearly need edits, return it unchanged.
12. When in doubt, keep the original wording.
13. Non-essential edits are forbidden.
14. If a difference is only a slight semantic nuance, word-order preference, rhythm preference, or stylistic preference, do not change it.
15. Do not normalize phrasing just because another wording sounds a little better.
16. Do not make a change unless the original wording contains a clear language mistake that a careful editor would definitely correct.
17. If the original sentence is understandable, grammatically acceptable, and not clearly wrong, keep it exactly as written.
18. Do not replace one valid word with another valid near-synonym just because the replacement is safer, more common, flatter, or more neutral.
19. Do not weaken the force, sharpness, criticism, vividness, or expressive strength of a sentence if the original wording is already correct.
20. If both the original wording and an alternative wording are acceptable, keep the original wording.
21. Treat expressive but grammatical wording as intentional authorial choice, not as an error.
22. Only change wording when the original contains a hard error or is obviously unnatural to a careful native reader.

Priority:
- Highest priority: preserve the original text.
- Second priority: fix only clear language errors.
- Lowest priority: improve only clearly broken machine-translated phrasing that would read as an actual language mistake.
- If there is any doubt, or if both versions can work, keep the original.

Publication standard note:
- "Publication-grade" here means error-free and naturally readable.
- It does NOT mean rewriting for style, elegance, stronger voice, smoother rhythm, or better phrasing.
- It also does NOT mean replacing vivid wording with milder wording, or replacing deliberate wording with more standard wording.

Source markdown:
$SourceText
"@

    $CallConfig = Copy-SageLlmConfig -Config $LlmConfig -ModelOverride $ModelName
    $OutputText = Invoke-SageLlmText -Prompt $Prompt -Config $CallConfig -MaxOutputTokens 8000

    if ([string]::IsNullOrWhiteSpace($OutputText)) {
        throw "Empty refine response for $RelativePath"
    }

    $InputTokens = 0
    $OutputTokens = 0
    $TotalTokens = 0

    return @{
        content = (Normalize-MarkdownOutput -Content $OutputText)
        usage = @{
            input_tokens  = $InputTokens
            output_tokens = $OutputTokens
            total_tokens  = $TotalTokens
        }
    }
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
$LlmConfig = Get-SageLlmConfig
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $LlmConfig.Model = $Model.Trim()
}

$LanguageProfile = Get-LanguageProfile -LanguageCode $Language
$TargetCode = $LanguageProfile.code
$TargetLanguageName = $LanguageProfile.name
$RefinePolicyVersion = "2026-04-18-strict-minimal-v3"
$NoChangeThreshold = 4
$SelectedModel = if ([string]::IsNullOrWhiteSpace($LlmConfig.Model)) { "codex-default" } else { $LlmConfig.Model }

Set-SageCurrentStep -Context $Context -Step "refine_translation" -Data @{
    language = $TargetCode
    model = $SelectedModel
    chapter = $Chapter
    start_chapter = $StartChapter
    end_chapter = $EndChapter
    all = [bool]$All
    force = [bool]$Force
}

$BookRoot = $Context.BookRoot
$TranslationRoot = Join-Path $BookRoot ("03_translation\" + $TargetCode)
$TargetBriefRoot = Join-Path $TranslationRoot "00_brief"
$TargetOutlineRoot = Join-Path $TranslationRoot "01_outline"
$TargetChapterRoot = Join-Path $TranslationRoot "02_chapters"
$ManifestPath = Join-Path $TranslationRoot "refine_manifest.json"
$BackupRoot = Join-Path $TranslationRoot "_refine_backups"

if (!(Test-Path $TranslationRoot)) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "Translation root not found." -Data @{ language = $TargetCode; translation_root = $TranslationRoot }
    Write-Output "ERROR: Translation root not found."
    exit 1
}

if (!(Test-Path $TargetChapterRoot)) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "Translated chapter folder not found." -Data @{ language = $TargetCode; chapter_root = $TargetChapterRoot }
    Write-Output "ERROR: Translated chapter folder not found."
    exit 1
}

$ChapterFiles = Get-ChildItem -LiteralPath $TargetChapterRoot -Filter *.md -File |
    Where-Object { $_.Name -notmatch "^_" } |
    Sort-Object Name

$TotalChapters = $ChapterFiles.Count
if ($TotalChapters -eq 0) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "No translated chapter files found." -Data @{ language = $TargetCode; chapter_root = $TargetChapterRoot }
    Write-Output "ERROR: No translated chapter files found."
    exit 1
}

if ($All -and ($Chapter -or $StartChapter -or $EndChapter)) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "Conflicting refine scope arguments." -Data @{
        language = $TargetCode
        chapter = $Chapter
        start_chapter = $StartChapter
        end_chapter = $EndChapter
        all = [bool]$All
    }
    Write-Output "ERROR: Cannot combine -All with chapter selection arguments."
    exit 1
}

if ($Chapter -and ($StartChapter -or $EndChapter)) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "Conflicting chapter arguments." -Data @{
        language = $TargetCode
        chapter = $Chapter
        start_chapter = $StartChapter
        end_chapter = $EndChapter
    }
    Write-Output "ERROR: Cannot use -Chapter with -StartChapter/-EndChapter."
    exit 1
}

if ($All -or (-not $Chapter -and -not $StartChapter -and -not $EndChapter)) {
    $StartIndex = 1
    $EndIndex = $TotalChapters
}
elseif ($Chapter) {
    if ($Chapter -lt 1 -or $Chapter -gt $TotalChapters) {
        Fail-SageStep -Context $Context -Step "refine_translation" -Message "Chapter out of range." -Data @{
            language = $TargetCode
            chapter = $Chapter
            chapter_count = $TotalChapters
        }
        Write-Output "ERROR: Chapter out of range."
        exit 1
    }

    $StartIndex = $Chapter
    $EndIndex = $Chapter
}
else {
    if (-not $StartChapter -or -not $EndChapter) {
        Fail-SageStep -Context $Context -Step "refine_translation" -Message "Chapter range missing boundary." -Data @{
            language = $TargetCode
            start_chapter = $StartChapter
            end_chapter = $EndChapter
        }
        Write-Output "ERROR: Both -StartChapter and -EndChapter must be specified."
        exit 1
    }

    if ($StartChapter -lt 1 -or $EndChapter -gt $TotalChapters -or $StartChapter -gt $EndChapter) {
        Fail-SageStep -Context $Context -Step "refine_translation" -Message "Invalid chapter range." -Data @{
            language = $TargetCode
            start_chapter = $StartChapter
            end_chapter = $EndChapter
            chapter_count = $TotalChapters
        }
        Write-Output "ERROR: Invalid chapter range."
        exit 1
    }

    $StartIndex = $StartChapter
    $EndIndex = $EndChapter
}

$PreviousManifestEntries = @{}
if (Test-Path $ManifestPath) {
    try {
        $PreviousManifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($PreviousManifest.entries) {
            foreach ($Entry in $PreviousManifest.entries) {
                if ($Entry.relative_path) {
                    $PreviousManifestEntries[$Entry.relative_path] = $Entry
                }
            }
        }
    }
    catch {
        Write-Output "WARN: Failed to read previous refine_manifest.json, continuing with a fresh run."
    }
}

$Candidates = New-Object System.Collections.Generic.List[object]

if ($All) {
    $CommonFiles = @(
        @{
            source = Join-Path $TargetBriefRoot "objective.md"
            role = "objective"
            relative = "00_brief/objective.md"
        }
    )

    $AmazonDescriptionTarget = Join-Path $TargetBriefRoot "amazon_description.md"
    if (Test-Path -LiteralPath $AmazonDescriptionTarget) {
        $CommonFiles += @{
            source = $AmazonDescriptionTarget
            role = "amazon_description"
            relative = "00_brief/amazon_description.md"
        }
    }

    $CommonFiles += @(
        @{
            source = Join-Path $TargetOutlineRoot "toc.md"
            role = "toc"
            relative = "01_outline/toc.md"
        }
    )

    foreach ($Item in $CommonFiles) {
        $Candidates.Add($Item)
    }
}

for ($i = $StartIndex; $i -le $EndIndex; $i++) {
    $ChapterFile = $ChapterFiles[$i - 1]
    $Candidates.Add(@{
        source = $ChapterFile.FullName
        role = "chapter"
        relative = "02_chapters/$($ChapterFile.Name)"
    })
}

$ExistingCandidates = @($Candidates | Where-Object { Test-Path $_.source })
if ($ExistingCandidates.Count -eq 0) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "No translated markdown files found for selected scope." -Data @{
        language = $TargetCode
        translation_root = $TranslationRoot
        start_chapter = $StartIndex
        end_chapter = $EndIndex
    }
    Write-Output "ERROR: No translated markdown files found for selected scope."
    exit 1
}

$StartTime = Get-Date
$BackupStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupSessionRoot = Join-Path $BackupRoot $BackupStamp
$BackupCreated = $false
$RefinedFiles = @()
$SkippedFiles = @()
$UnchangedFiles = @()
$NoChangeMarkedFiles = @()
$MissingFiles = @()
$ManifestEntries = @()
$DiffFiles = @()
$TotalInputTokens = 0
$TotalOutputTokens = 0
$TotalTokens = 0
$TotalDifferencePoints = 0

foreach ($Item in $Candidates) {
    if (!(Test-Path $Item.source)) {
        $MissingFiles += $Item.relative
        Write-Output "$($Item.relative) not found. Skipping."
        continue
    }

    Write-Output "Checking previous refine state for $($Item.relative)"
    $SourceText = Get-Content -LiteralPath $Item.source -Raw -Encoding UTF8
    $SourceHash = Get-TextHash -Content $SourceText
    $PreviousEntry = $PreviousManifestEntries[$Item.relative]
    $HasSameSourceHash = $PreviousEntry -and ($PreviousEntry.source_hash -eq $SourceHash)
    $HasCompatiblePreviousEntry = $HasSameSourceHash -and `
        ($PreviousEntry.model -eq $SelectedModel) -and `
        ($PreviousEntry.policy_version -eq $RefinePolicyVersion)

    if ($PreviousEntry) {
        Write-Output "$($Item.relative) has a previous refine record."
        if ($HasSameSourceHash) {
            Write-Output "$($Item.relative) source hash is unchanged since the previous refine record."
        }
        else {
            Write-Output "$($Item.relative) source content changed since the previous refine record."
        }
    }
    else {
        Write-Output "$($Item.relative) has no previous refine record."
    }

    if ((-not $Force) -and $HasSameSourceHash -and $PreviousEntry.no_change_confirmed) {
        $SkippedFiles += $Item.relative
        $NoChangeMarkedFiles += $Item.relative
        Write-Output "$($Item.relative) previously confirmed as no-change. Skipping before API call."
        continue
    }

    if ((-not $Force) -and $HasCompatiblePreviousEntry) {
        if ($PreviousEntry.no_change_confirmed) {
            $SkippedFiles += $Item.relative
            $NoChangeMarkedFiles += $Item.relative
            Write-Output "$($Item.relative) previously confirmed as no-change under the current refine policy. Skipping."
            continue
        }

        $SkippedFiles += $Item.relative
        Write-Output "$($Item.relative) already refined with the current model and policy, and the source is unchanged. Skipping."
        continue
    }

    Write-Output "Refining $($Item.relative) -> $TargetCode"
    Write-Output "API call starting for $($Item.relative) with model $SelectedModel"

    try {
        $Result = Get-RefineResult -SourceText $SourceText -ModelName $SelectedModel -TargetLanguageName $TargetLanguageName -FileRole $Item.role -RelativePath $Item.relative
        $RefinedText = $Result.content
        $RefinedHash = Get-TextHash -Content $RefinedText
        $DiffPointCount = 0
        $NoChangeConfirmed = $false
        $Decision = "changed"

        if ($RefinedHash -ne $SourceHash) {
            if (-not $BackupCreated) {
                New-Item -ItemType Directory -Path $BackupSessionRoot -Force | Out-Null
                $BackupCreated = $true
            }

            $BackupPath = Join-Path $BackupSessionRoot ($Item.relative -replace "/", "\")
            $BackupDir = Split-Path -Parent $BackupPath
            if (!(Test-Path $BackupDir)) {
                New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
            }

            Copy-Item -LiteralPath $Item.source -Destination $BackupPath -Force
            $DiffPath = [System.IO.Path]::ChangeExtension($BackupPath, ".diff.md")
            $OriginalSentences = Split-TextSentences -Content $SourceText
            $RefinedSentences = Split-TextSentences -Content $RefinedText
            $DiffPoints = Get-SentenceDiffPoints -OriginalSentences $OriginalSentences -RefinedSentences $RefinedSentences
            $DiffPointCount = $DiffPoints.Count
            $NoChangeConfirmed = ($DiffPointCount -lt $NoChangeThreshold)
            if ($NoChangeConfirmed) {
                $NoChangeMarkedFiles += $Item.relative
                $Decision = "minor_change_stable"
                Write-Output "$($Item.relative) has only $DiffPointCount difference point(s), so it will be treated as no-change on the next run."
            }
            $DiffContent = New-DiffReportContent -RelativePath $Item.relative -OriginalText $SourceText -RefinedText $RefinedText
            Save-Utf8File -Path $DiffPath -Content $DiffContent
            Save-Utf8File -Path $Item.source -Content $RefinedText
            $RefinedFiles += $Item.relative
            $DiffFiles += ($DiffPath.Substring($BackupSessionRoot.Length).TrimStart("\"))
            Write-Output "$($Item.relative) refined content saved. Difference points: $DiffPointCount"
        }
        else {
            $UnchangedFiles += $Item.relative
            $NoChangeMarkedFiles += $Item.relative
            $NoChangeConfirmed = $true
            $Decision = "no_change"
            Write-Output "$($Item.relative) returned unchanged after API review. Difference points: 0"
        }

        $ManifestEntries += [ordered]@{
            relative_path = $Item.relative
            file_role = $Item.role
            source_hash = $RefinedHash
            changed = ($RefinedHash -ne $SourceHash)
            no_change_confirmed = $NoChangeConfirmed
            decision = $Decision
            diff_point_count = $DiffPointCount
            model = $SelectedModel
            policy_version = $RefinePolicyVersion
            refined_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        $TotalInputTokens += $Result.usage.input_tokens
        $TotalOutputTokens += $Result.usage.output_tokens
        $TotalTokens += $Result.usage.total_tokens
        $TotalDifferencePoints += $DiffPointCount
        Write-Output "Usage for $($Item.relative): input=$($Result.usage.input_tokens), output=$($Result.usage.output_tokens), total=$($Result.usage.total_tokens)"
    }
    catch {
        Fail-SageStep -Context $Context -Step "refine_translation" -Message "Failed to refine translated markdown file." -Data @{
            language = $TargetCode
            file = $Item.relative
            error = $_.Exception.Message
        }
        Write-Output "ERROR: Failed refining $($Item.relative)"
        Write-Output "DETAIL: $($_.Exception.Message)"
        exit 1
    }
}

$Manifest = [ordered]@{
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    book_name = $BookName
    target_language = $TargetCode
    target_language_name = $TargetLanguageName
    policy_version = $RefinePolicyVersion
    no_change_threshold = $NoChangeThreshold
    scope = if ($All) { "all" } elseif ($Chapter) { "single" } elseif ($StartChapter -or $EndChapter) { "range" } else { "all" }
    chapter_range = @{
        start = $StartIndex
        end = $EndIndex
        total_chapters = $TotalChapters
    }
    refined_files = $RefinedFiles
    diff_files = $DiffFiles
    unchanged_files = $UnchangedFiles
    no_change_marked_files = $NoChangeMarkedFiles
    skipped_files = $SkippedFiles
    missing_files = $MissingFiles
    backup_root = if ($BackupCreated) { $BackupSessionRoot } else { "" }
    difference_points_total = $TotalDifferencePoints
    usage = @{
        input_tokens = $TotalInputTokens
        output_tokens = $TotalOutputTokens
        total_tokens = $TotalTokens
        model = $SelectedModel
    }
    entries = $ManifestEntries
}

$Manifest | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $ManifestPath -Encoding utf8

$Duration = [math]::Round(((Get-Date) - $StartTime).TotalSeconds, 2)
Complete-SageStep -Context $Context -Step "refine_translation" -State "success" -Message "Translation refinement completed." -Data @{
    language = $TargetCode
    refined_file_count = $RefinedFiles.Count
    diff_file_count = $DiffFiles.Count
    unchanged_file_count = $UnchangedFiles.Count
    no_change_marked_file_count = $NoChangeMarkedFiles.Count
    skipped_file_count = $SkippedFiles.Count
    missing_file_count = $MissingFiles.Count
    difference_points_total = $TotalDifferencePoints
    processed_range = "$StartIndex-$EndIndex"
    duration_seconds = $Duration
    translation_root = $TranslationRoot
    backup_root = if ($BackupCreated) { $BackupSessionRoot } else { "" }
    model = $SelectedModel
    input_tokens_total = $TotalInputTokens
    output_tokens_total = $TotalOutputTokens
    total_tokens_total = $TotalTokens
}

Write-Output "SUCCESS: Translation refinement completed for $TargetCode."
Write-Output "Model: $SelectedModel"
Write-Output "Translation root: $TranslationRoot"
Write-Output "Manifest: $ManifestPath"
Write-Output "No-change threshold: fewer than $NoChangeThreshold difference points"
Write-Output "Refined files: $($RefinedFiles.Count)"
Write-Output "Unchanged files: $($UnchangedFiles.Count)"
Write-Output "No-change marked files: $($NoChangeMarkedFiles.Count)"
Write-Output "Skipped files: $($SkippedFiles.Count)"
Write-Output "Missing files: $($MissingFiles.Count)"
Write-Output "Difference points total: $TotalDifferencePoints"
Write-Output "Token usage total: input=$TotalInputTokens, output=$TotalOutputTokens, total=$TotalTokens"
if ($RefinedFiles.Count -eq 0 -and $UnchangedFiles.Count -gt 0) {
    Write-Output "Result: This run found no files that required modification."
}
elseif ($RefinedFiles.Count -eq 0 -and $NoChangeMarkedFiles.Count -gt 0 -and $SkippedFiles.Count -gt 0) {
    Write-Output "Result: These files were previously confirmed as no-change and were skipped."
}
if ($BackupCreated) {
    Write-Output "Backup root: $BackupSessionRoot"
}
