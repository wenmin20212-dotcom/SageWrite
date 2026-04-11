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

function Write-TextUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Get-RelativePathSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

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

function Get-AmazonCategories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookType,

        [Parameter(Mandatory = $true)]
        [string]$Audience,

        [Parameter(Mandatory = $true)]
        [string]$CoreThesis
    )

    $Combined = @($BookType, $Audience, $CoreThesis) -join " "

    if ($Combined -match "小说|fiction|novel") {
        return @(
            "Fiction / Literary",
            "Fiction / Contemporary"
        )
    }

    if ($Combined -match "教育|教材|teaching|education") {
        return @(
            "Education / Teaching Methods & Materials",
            "Language Arts & Disciplines / Writing / General"
        )
    }

    if ($Combined -match "AI|人工智能|智能|technology|digital") {
        return @(
            "Computers / Artificial Intelligence / General",
            "Language Arts & Disciplines / Writing / General"
        )
    }

    return @(
        "Non-Classifiable",
        "Language Arts & Disciplines / Writing / General"
    )
}

function Get-AmazonKeywordBoxes {
    param(
        [string[]]$Keywords
    )

    $Result = @()
    foreach ($Keyword in $Keywords) {
        $Value = "$Keyword".Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) {
            continue
        }
        $Result += $Value
        if ($Result.Count -ge 7) {
            break
        }
    }
    return $Result
}

function Get-FallbackKeywords {
    param(
        [string]$Title,
        [string]$Subtitle,
        [string]$BookType,
        [string]$CoreThesis
    )

    $Seeds = @(
        "$Title",
        "$Subtitle",
        "$BookType",
        "SageWrite",
        "AI writing",
        "artificial intelligence",
        "knowledge creation",
        "structured writing",
        "digital publishing",
        "$CoreThesis"
    )

    return @($Seeds | ForEach-Object { "$_".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-PrimaryManuscriptFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AmazonRoot
    )

    $Preferred = @("book.epub", "book.docx", "book.pdf")
    foreach ($Name in $Preferred) {
        $Path = Join-Path $AmazonRoot $Name
        if (Test-Path -LiteralPath $Path) {
            return $Path
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

Set-SageCurrentStep -Context $Context -Step "publish_amazon" -Data @{
    language = $LanguageCode
}

$BookRoot = $Context.BookRoot
$PublishRoot = Join-Path $BookRoot ("09_publish\" + $LanguageCode)
$AmazonRoot = Join-Path $PublishRoot "amazon"
$MetadataPath = Join-Path $PublishRoot "publish_metadata.json"
$ManifestPath = Join-Path $PublishRoot "publish_manifest.json"
$AmazonMetadataPath = Join-Path $AmazonRoot "metadata.json"
$AmazonPackagePath = Join-Path $AmazonRoot "amazon_kdp_package.json"
$AmazonDescriptionPath = Join-Path $AmazonRoot "amazon_description.txt"
$AmazonKeywordsPath = Join-Path $AmazonRoot "amazon_keywords.txt"
$AmazonChecklistPath = Join-Path $AmazonRoot "amazon_submission_checklist.md"

if (-not (Test-Path -LiteralPath $MetadataPath)) {
    Fail-SageStep -Context $Context -Step "publish_amazon" -Message "publish_metadata.json not found." -Data @{
        language = $LanguageCode
        publish_root = $PublishRoot
        metadata = $MetadataPath
    }
    Write-Error "publish_metadata.json not found: $MetadataPath"
    exit 1
}

Ensure-Directory -Path $AmazonRoot

if ((Test-Path -LiteralPath $AmazonPackagePath) -and (-not $Force)) {
    Write-Host "amazon_kdp_package.json already exists. Use -Force to regenerate."
    exit 0
}

$PublishMetadata = Get-Content -LiteralPath $MetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Manifest = if (Test-Path -LiteralPath $ManifestPath) {
    Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $null
}

$AmazonMetadata = if (Test-Path -LiteralPath $AmazonMetadataPath) {
    Get-Content -LiteralPath $AmazonMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $null
}

$SourceKeywords = @($PublishMetadata.keywords | ForEach-Object { "$_" })
if ($SourceKeywords.Count -eq 0) {
    $SourceKeywords = Get-FallbackKeywords -Title "$($PublishMetadata.title)" -Subtitle "$($PublishMetadata.subtitle)" -BookType "$($PublishMetadata.book_type)" -CoreThesis "$($PublishMetadata.core_thesis)"
}
$KeywordBoxes = Get-AmazonKeywordBoxes -Keywords $SourceKeywords
$AmazonRecommended = @($PublishMetadata.platform_recommended_categories.amazon | ForEach-Object { "$($_.path)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$AmazonSelected = "$($PublishMetadata.platform_selected_categories.amazon)".Trim()
$AmazonCategories = if (-not [string]::IsNullOrWhiteSpace($AmazonSelected)) {
    @($AmazonSelected) + @($AmazonRecommended | Where-Object { $_ -ne $AmazonSelected })
} elseif ($AmazonRecommended.Count -gt 0) {
    $AmazonRecommended
} else {
    Get-AmazonCategories -BookType "$($PublishMetadata.book_type)" -Audience "$($PublishMetadata.audience)" -CoreThesis "$($PublishMetadata.core_thesis)"
}
$AmazonCategories = @($AmazonCategories | Select-Object -Unique)
$ManuscriptPath = Get-PrimaryManuscriptFile -AmazonRoot $AmazonRoot
$CoverPath = Join-Path $AmazonRoot "cover.png"
if (-not (Test-Path -LiteralPath $CoverPath)) {
    $CoverPath = Join-Path $AmazonRoot "cover.jpg"
}
if (-not (Test-Path -LiteralPath $CoverPath)) {
    $CoverPath = Join-Path $AmazonRoot "cover.jpeg"
}

$AmazonPackage = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    platform = "amazon_kdp"
    language = $LanguageCode
    package_ready = $true
    submission_type = "ebook"
    book_details = [ordered]@{
        title = "$($PublishMetadata.title)"
        subtitle = "$($PublishMetadata.subtitle)"
        author = "$($PublishMetadata.author)"
        description = "$($PublishMetadata.long_description)"
        short_description = "$($PublishMetadata.short_description)"
        keywords = @($KeywordBoxes)
        categories = @($AmazonCategories)
        language = "$($PublishMetadata.language_name)"
        publisher = "$($PublishMetadata.publisher)"
        imprint = "$($PublishMetadata.imprint)"
        publication_date = "$($PublishMetadata.publication_date)"
        rights = "$($PublishMetadata.rights)"
        territory = "$($PublishMetadata.territory)"
        edition_type = "$($PublishMetadata.edition_type)"
    }
    upload_assets = [ordered]@{
        manuscript = if ($ManuscriptPath) { Get-RelativePathSafe -BasePath $BookRoot -TargetPath $ManuscriptPath } else { $null }
        cover = if (Test-Path -LiteralPath $CoverPath) { Get-RelativePathSafe -BasePath $BookRoot -TargetPath $CoverPath } else { $null }
        metadata = if (Test-Path -LiteralPath $AmazonMetadataPath) { Get-RelativePathSafe -BasePath $BookRoot -TargetPath $AmazonMetadataPath } else { $null }
    }
    quality_checks = [ordered]@{
        has_title = (-not [string]::IsNullOrWhiteSpace("$($PublishMetadata.title)"))
        has_author = (-not [string]::IsNullOrWhiteSpace("$($PublishMetadata.author)"))
        has_description = (-not [string]::IsNullOrWhiteSpace("$($PublishMetadata.long_description)"))
        has_cover = (Test-Path -LiteralPath $CoverPath)
        has_manuscript = ($null -ne $ManuscriptPath)
        keyword_box_count = $KeywordBoxes.Count
        category_count = $AmazonCategories.Count
    }
    manual_fields = [ordered]@{
        age_range = ""
        marketplace = "amazon.com"
        primary_category_override = ""
        secondary_category_override = ""
        pricing_notes = "Set pricing manually in KDP."
        drm_setting = "Decide manually in KDP."
    }
}

if (-not $AmazonPackage.quality_checks.has_cover -or -not $AmazonPackage.quality_checks.has_manuscript) {
    $AmazonPackage.package_ready = $false
}

$AmazonPackage | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $AmazonPackagePath -Encoding UTF8

$DescriptionText = @(
    "$($PublishMetadata.title)",
    "",
    "$($PublishMetadata.long_description)"
) -join "`r`n"
Write-TextUtf8 -Path $AmazonDescriptionPath -Content $DescriptionText

$KeywordLines = @()
for ($i = 0; $i -lt $KeywordBoxes.Count; $i++) {
    $KeywordLines += ("Keyword Box {0}: {1}" -f ($i + 1), $KeywordBoxes[$i])
}
Write-TextUtf8 -Path $AmazonKeywordsPath -Content ($KeywordLines -join "`r`n")

$ChecklistLines = @()
$ChecklistLines += "# Amazon KDP Submission Checklist"
$ChecklistLines += ""
$ChecklistLines += "- Title: $($PublishMetadata.title)"
$ChecklistLines += "- Subtitle: $($PublishMetadata.subtitle)"
$ChecklistLines += "- Author: $($PublishMetadata.author)"
$ChecklistLines += "- Language: $($PublishMetadata.language_name)"
$ChecklistLines += "- Submission type: ebook"
$ChecklistLines += ""
$ChecklistLines += "## Upload Assets"
$ChecklistLines += ""
$ChecklistLines += "- Manuscript: $($AmazonPackage.upload_assets.manuscript)"
$ChecklistLines += "- Cover: $($AmazonPackage.upload_assets.cover)"
$ChecklistLines += "- Metadata: $($AmazonPackage.upload_assets.metadata)"
$ChecklistLines += ""
$ChecklistLines += "## Description"
$ChecklistLines += ""
$ChecklistLines += "$($PublishMetadata.long_description)"
$ChecklistLines += ""
$ChecklistLines += "## Keyword Boxes"
$ChecklistLines += ""
$KeywordBoxes | ForEach-Object { $ChecklistLines += "- $_" }
$ChecklistLines += ""
$ChecklistLines += "## Recommended Categories"
$ChecklistLines += ""
$AmazonCategories | ForEach-Object { $ChecklistLines += "- $_" }
$ChecklistLines += ""
$ChecklistLines += "## Manual Review Before Upload"
$ChecklistLines += ""
$ChecklistLines += "- Confirm EPUB opens correctly in Kindle Previewer or another EPUB validator"
$ChecklistLines += "- Confirm cover image is the final approved version"
$ChecklistLines += "- Confirm long description is suitable for the Amazon store page"
$ChecklistLines += "- Confirm categories and keyword boxes match the intended market"
$ChecklistLines += "- Set pricing, territory, DRM, and publishing rights manually in KDP"

Write-TextUtf8 -Path $AmazonChecklistPath -Content ($ChecklistLines -join "`r`n")

Write-Host ""
Write-Host "09c-amazon completed successfully."
Write-Host ("Amazon package: " + $AmazonPackagePath)
Write-Host ("Checklist:      " + $AmazonChecklistPath)

Complete-SageStep -Context $Context -Step "publish_amazon" -State "success" -Message "Amazon KDP package prepared." -Data @{
    language = $LanguageCode
    amazon_root = $AmazonRoot
    package = $AmazonPackagePath
    checklist = $AmazonChecklistPath
    keyword_boxes = $KeywordBoxes.Count
    category_count = $AmazonCategories.Count
    package_ready = $AmazonPackage.package_ready
}
