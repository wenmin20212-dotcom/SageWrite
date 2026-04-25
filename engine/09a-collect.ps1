param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$Force
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-FrontMatterValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $Normalized = $Content -replace "`r", ""
    if (-not $Normalized.StartsWith("---`n")) {
        return $null
    }

    $Match = [regex]::Match($Normalized, "(?s)^---\n(.*?)\n---\n?")
    if (-not $Match.Success) {
        return $null
    }

    $Pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+?)\s*$"
    $ValueMatch = [regex]::Match($Match.Groups[1].Value, $Pattern)
    if (-not $ValueMatch.Success) {
        return $null
    }

    return $ValueMatch.Groups[1].Value.Trim().Trim('"').Trim("'")
}

function Get-RelativePathOrNull {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        return $null
    }

    $BaseFull = [System.IO.Path]::GetFullPath($BasePath)
    if (-not $BaseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $BaseFull += [System.IO.Path]::DirectorySeparatorChar
    }
    $TargetFull = [System.IO.Path]::GetFullPath($TargetPath)
    $BaseUri = New-Object System.Uri($BaseFull)
    $TargetUri = New-Object System.Uri($TargetFull)
    $RelativeUri = $BaseUri.MakeRelativeUri($TargetUri)
    return [System.Uri]::UnescapeDataString($RelativeUri.ToString()).Replace('/', '\')
}

function Get-OutputLanguageRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookRoot,

        [Parameter(Mandatory = $true)]
        [string]$LanguageCode
    )

    $OutputBaseRoot = Join-Path $BookRoot "04_output"
    $LanguageRoot = Join-Path $OutputBaseRoot $LanguageCode
    if (($LanguageCode -eq "zh") -and (-not (Test-Path -LiteralPath $LanguageRoot))) {
        return $OutputBaseRoot
    }
    return $LanguageRoot
}

function Get-LanguageSourceRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookRoot,

        [Parameter(Mandatory = $true)]
        [string]$LanguageCode
    )

    if ($LanguageCode -eq "zh") {
        return $null
    }

    $TranslationRoot = Join-Path $BookRoot ("03_translation\" + $LanguageCode)
    if (Test-Path -LiteralPath $TranslationRoot) {
        return $TranslationRoot
    }

    return $null
}

function Get-LocalizedSourcePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookRoot,

        [Parameter(Mandatory = $true)]
        [string]$LanguageCode,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $LanguageRoot = Get-LanguageSourceRoot -BookRoot $BookRoot -LanguageCode $LanguageCode
    if ($null -ne $LanguageRoot) {
        $LocalizedPath = Join-Path $LanguageRoot $RelativePath
        if (Test-Path -LiteralPath $LocalizedPath) {
            return $LocalizedPath
        }
    }

    return Join-Path $BookRoot $RelativePath
}

function Get-ChapterTitlesFromRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChapterRoot
    )

    if (-not (Test-Path -LiteralPath $ChapterRoot)) {
        return @()
    }

    $Files = Get-ChildItem -LiteralPath $ChapterRoot -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^\d+\.md$'
    } | Sort-Object Name

    $Titles = New-Object System.Collections.Generic.List[string]
    foreach ($File in $Files) {
        $Raw = Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8
        $Title = Get-FrontMatterValue -Content $Raw -Key "title"
        if ([string]::IsNullOrWhiteSpace($Title)) {
            $Title = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
        }

        if (-not [string]::IsNullOrWhiteSpace($Title)) {
            $Titles.Add($Title.Trim())
        }
    }

    return @($Titles)
}

function Get-FirstSentence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $Value = "$Text".Trim()
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $Parts = [regex]::Split($Value, '[\u3002\uFF01\uFF1F.!?]+')
    foreach ($Part in $Parts) {
        $Candidate = "$Part".Trim()
        if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
            return $Candidate
        }
    }

    return $Value
}

function Get-PrimaryOutputFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string[]]$Extensions
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    $NormalizedExtensions = @($Extensions | ForEach-Object { $_.ToLowerInvariant() })
    $Files = Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue | Where-Object {
        ($NormalizedExtensions -contains $_.Extension.ToLowerInvariant()) -and
        ($_.Name -notmatch '^~\$')
    } | Sort-Object LastWriteTime -Descending

    if ($Files.Count -gt 0) {
        return $Files[0].FullName
    }

    return $null
}

function Get-CoverRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookRoot,

        [Parameter(Mandatory = $true)]
        [string]$Edition
    )

    $BaseRoot = Join-Path $BookRoot "07_cover"
    $EditionRoot = Join-Path $BaseRoot $Edition
    if (Test-Path -LiteralPath $EditionRoot) {
        return $EditionRoot
    }
    return $BaseRoot
}

function Get-PrimaryCoverFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookRoot,

        [Parameter(Mandatory = $true)]
        [string]$LanguageCode,

        [Parameter(Mandatory = $true)]
        [string]$CoverFinalRoot
    )

    $PrimaryNames = @(
        "cover.png",
        "cover.jpg",
        "cover.jpeg",
        "cover.webp"
    )
    $FinalNames = @(
        "cover_final_front.png",
        "cover_final_front.jpg",
        "cover_final_front.jpeg",
        "cover_final_front.webp"
    )

    $PrimaryRoots = New-Object System.Collections.Generic.List[string]
    $LocalizedRoot = Get-LanguageSourceRoot -BookRoot $BookRoot -LanguageCode $LanguageCode
    if ($null -ne $LocalizedRoot -and (Test-Path -LiteralPath $LocalizedRoot)) {
        $PrimaryRoots.Add($LocalizedRoot)
        $LocalizedChapterRoot = Join-Path $LocalizedRoot "02_chapters"
        if (Test-Path -LiteralPath $LocalizedChapterRoot) {
            $PrimaryRoots.Add($LocalizedChapterRoot)
        }
    }
    else {
        $PrimaryRoots.Add($BookRoot)
        $BookChapterRoot = Join-Path $BookRoot "02_chapters"
        if (Test-Path -LiteralPath $BookChapterRoot) {
            $PrimaryRoots.Add($BookChapterRoot)
        }
    }

    foreach ($Root in ($PrimaryRoots | Select-Object -Unique)) {
        foreach ($name in $PrimaryNames) {
            $Path = Join-Path $Root $name
            if (Test-Path -LiteralPath $Path) {
                return $Path
            }
        }
    }

    if (Test-Path -LiteralPath $CoverFinalRoot) {
        foreach ($name in $FinalNames) {
            $Path = Join-Path $CoverFinalRoot $name
            if (Test-Path -LiteralPath $Path) {
                return $Path
            }
        }
    }

    foreach ($Root in ($PrimaryRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $Root)) {
            continue
        }
        $Fallback = Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue | Where-Object {
            @(".png", ".jpg", ".jpeg", ".webp") -contains $_.Extension.ToLowerInvariant()
        } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if ($Fallback) {
            return $Fallback.FullName
        }
    }

    if (Test-Path -LiteralPath $CoverFinalRoot) {
        $Fallback = Get-ChildItem -LiteralPath $CoverFinalRoot -File -ErrorAction SilentlyContinue | Where-Object {
            @(".png", ".jpg", ".jpeg", ".webp") -contains $_.Extension.ToLowerInvariant()
        } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($Fallback) {
            return $Fallback.FullName
        }
    }

    return $null
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context

$LanguageCode = $Language.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    $LanguageCode = "zh"
}

Set-SageCurrentStep -Context $Context -Step "publish_collect" -Data @{
    language = $LanguageCode
}

$BookRoot = $Context.BookRoot
$ObjectivePath = Get-LocalizedSourcePath -BookRoot $BookRoot -LanguageCode $LanguageCode -RelativePath "00_brief\objective.md"
$LocalizedTocPath = Get-LocalizedSourcePath -BookRoot $BookRoot -LanguageCode $LanguageCode -RelativePath "01_outline\toc.md"
$LocalizedChapterRoot = Get-LocalizedSourcePath -BookRoot $BookRoot -LanguageCode $LanguageCode -RelativePath "02_chapters"
$CoverRoot = Get-CoverRoot -BookRoot $BookRoot -Edition "ebook"
$CoverBriefRoot = Join-Path $CoverRoot "brief"
$CoverFinalRoot = Join-Path $CoverRoot "final"
$PublishRoot = Join-Path $BookRoot ("09_publish\" + $LanguageCode)
$AssetsPath = Join-Path $PublishRoot "publish_assets.json"
$OutputRoot = Get-OutputLanguageRoot -BookRoot $BookRoot -LanguageCode $LanguageCode
$BriefJsonPath = Join-Path $CoverBriefRoot "cover_brief.json"
$CoverCopyJsonPath = Join-Path $CoverBriefRoot "cover_copy.json"

if (-not (Test-Path -LiteralPath $BookRoot)) {
    Fail-SageStep -Context $Context -Step "publish_collect" -Message "Book root not found." -Data @{
        book_root = $BookRoot
        language = $LanguageCode
    }
    Write-Error "Book root not found: $BookRoot"
    exit 1
}

if (-not (Test-Path -LiteralPath $ObjectivePath)) {
    Fail-SageStep -Context $Context -Step "publish_collect" -Message "objective.md not found." -Data @{
        objective = $ObjectivePath
        language = $LanguageCode
    }
    Write-Error "objective.md not found: $ObjectivePath"
    exit 1
}

Ensure-Directory -Path $PublishRoot

$ObjectiveRaw = Get-Content -LiteralPath $ObjectivePath -Raw -Encoding UTF8
$Title = Get-FrontMatterValue -Content $ObjectiveRaw -Key "title"
$SubtitleMatch = [regex]::Match(($ObjectiveRaw -replace "`r", ""), '(?m)^subtitle:\s*(.+?)\s*$')
$Subtitle = if ($SubtitleMatch.Success) {
    $SubtitleMatch.Groups[1].Value.Trim().Trim('"').Trim("'")
} else {
    ""
}
$Author = Get-FrontMatterValue -Content $ObjectiveRaw -Key "author"
$Audience = Get-FrontMatterValue -Content $ObjectiveRaw -Key "audience"
$BookType = Get-FrontMatterValue -Content $ObjectiveRaw -Key "type"
$Style = Get-FrontMatterValue -Content $ObjectiveRaw -Key "style"
$Scope = Get-FrontMatterValue -Content $ObjectiveRaw -Key "scope"

$EpubPath = Get-PrimaryOutputFile -Root $OutputRoot -Extensions @(".epub")
$PdfPath = Get-PrimaryOutputFile -Root $OutputRoot -Extensions @(".pdf")
$DocxPath = Get-PrimaryOutputFile -Root $OutputRoot -Extensions @(".docx")
$CoverPath = Get-PrimaryCoverFile -BookRoot $BookRoot -LanguageCode $LanguageCode -CoverFinalRoot $CoverFinalRoot

$CoverCopy = $null
$CoverBrief = $null
if (Test-Path -LiteralPath $BriefJsonPath) {
    try {
        $CoverBrief = Get-Content -LiteralPath $BriefJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $CoverBrief = $null
    }
}

if (Test-Path -LiteralPath $CoverCopyJsonPath) {
    try {
        $CoverCopy = Get-Content -LiteralPath $CoverCopyJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $CoverCopy = $null
    }
}

$SelectedCopy = if ($null -ne $CoverCopy) { $CoverCopy.selected } else { $null }
$BriefKeywords = if (($LanguageCode -eq "zh") -and $null -ne $CoverBrief -and $null -ne $CoverBrief.metadata) {
    @($CoverBrief.metadata.top_keywords | ForEach-Object { "$_" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
} else {
    @()
}
$CoreThesis = if (-not [string]::IsNullOrWhiteSpace((Get-FrontMatterValue -Content $ObjectiveRaw -Key "core_thesis"))) {
    (Get-FrontMatterValue -Content $ObjectiveRaw -Key "core_thesis")
} elseif ($null -ne $CoverBrief -and $null -ne $CoverBrief.metadata) {
    "$($CoverBrief.metadata.core_thesis)"
} else {
    ""
}
$ChapterCount = if ((Test-Path -LiteralPath $LocalizedChapterRoot) -and $ChapterTitles.Count -gt 0) {
    $ChapterTitles.Count
} elseif ($null -ne $CoverBrief -and $null -ne $CoverBrief.metadata) {
    [int]$CoverBrief.metadata.chapter_count
} else {
    0
}
$ChapterTitles = if (Test-Path -LiteralPath $LocalizedChapterRoot) {
    Get-ChapterTitlesFromRoot -ChapterRoot $LocalizedChapterRoot
} elseif ($null -ne $CoverBrief -and $null -ne $CoverBrief.metadata) {
    @($CoverBrief.metadata.chapter_titles | ForEach-Object { "$_" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
} else {
    @()
}

$FallbackHook = if ($CoreThesis) { Get-FirstSentence -Text $CoreThesis } else { "" }
$FallbackBlurb = if ($CoreThesis) { $CoreThesis } else { "$Scope" }
$FallbackSpine = if ($Title) { $Title } else { $BookName }

$Assets = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    language = $LanguageCode
    source = [ordered]@{
        objective = Get-RelativePathOrNull -BasePath $BookRoot -TargetPath $ObjectivePath
        output_root = Get-RelativePathOrNull -BasePath $BookRoot -TargetPath $OutputRoot
        cover_root = Get-RelativePathOrNull -BasePath $BookRoot -TargetPath $CoverRoot
    }
    book = [ordered]@{
        title = if ($Title) { $Title } else { $BookName }
        subtitle = if ($Subtitle) { $Subtitle } else { "" }
        author = if ($Author) { $Author } else { "" }
        audience = if ($Audience) { $Audience } else { "" }
        type = if ($BookType) { $BookType } else { "" }
        style = if ($Style) { $Style } else { "" }
        scope = if ($Scope) { $Scope } else { "" }
        core_thesis = $CoreThesis
    }
    files = [ordered]@{
        epub = Get-RelativePathOrNull -BasePath $BookRoot -TargetPath $EpubPath
        pdf = Get-RelativePathOrNull -BasePath $BookRoot -TargetPath $PdfPath
        docx = Get-RelativePathOrNull -BasePath $BookRoot -TargetPath $DocxPath
        cover = Get-RelativePathOrNull -BasePath $BookRoot -TargetPath $CoverPath
    }
    marketing = [ordered]@{
        subtitle = if ($SelectedCopy -and -not [string]::IsNullOrWhiteSpace("$($SelectedCopy.subtitle)")) { "$($SelectedCopy.subtitle)" } elseif ($Subtitle) { $Subtitle } else { "" }
        tagline = if (($LanguageCode -eq "zh") -and $SelectedCopy) { "$($SelectedCopy.marketing_tagline)" } else { "" }
        hook = if (($LanguageCode -eq "zh") -and $SelectedCopy) { "$($SelectedCopy.back_cover_hook)" } else { $FallbackHook }
        blurb = if (($LanguageCode -eq "zh") -and $SelectedCopy) { "$($SelectedCopy.back_cover_blurb)" } else { $FallbackBlurb }
        obi_copy = if (($LanguageCode -eq "zh") -and $SelectedCopy) { "$($SelectedCopy.obi_copy)" } else { "" }
        author_bio = if (($LanguageCode -eq "zh") -and $SelectedCopy) { "$($SelectedCopy.author_bio)" } else { "" }
        spine_text = if (($LanguageCode -eq "zh") -and $SelectedCopy) { "$($SelectedCopy.spine_text)" } else { $FallbackSpine }
    }
    discovery = [ordered]@{
        keywords = @($BriefKeywords)
        chapter_count = $ChapterCount
        chapter_titles = @($ChapterTitles)
    }
}

$Assets | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $AssetsPath -Encoding UTF8

Write-Host ""
Write-Host "09a-collect completed successfully."
Write-Host ("Assets: " + $AssetsPath)

Complete-SageStep -Context $Context -Step "publish_collect" -State "success" -Message "Publish assets collected." -Data @{
    language = $LanguageCode
    publish_root = $PublishRoot
    assets = $AssetsPath
    epub = $EpubPath
    pdf = $PdfPath
    docx = $DocxPath
    cover = $CoverPath
}
