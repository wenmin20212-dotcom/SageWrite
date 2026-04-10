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

function Get-GoogleCategories {
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
            "Fiction / General",
            "Literary Collections"
        )
    }

    if ($Combined -match "教育|教材|teaching|education") {
        return @(
            "Education / General",
            "Study Aids / General"
        )
    }

    if ($Combined -match "AI|人工智能|智能|technology|digital") {
        return @(
            "Computers / Artificial Intelligence / General",
            "Language Arts & Disciplines / Writing / General"
        )
    }

    return @(
        "Nonfiction / General",
        "Language Arts & Disciplines / Writing / General"
    )
}

function Get-GoogleKeywords {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Keywords
    )

    $Result = @()
    foreach ($Keyword in $Keywords) {
        $Value = "$Keyword".Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) {
            continue
        }
        $Result += $Value
        if ($Result.Count -ge 12) {
            break
        }
    }
    return $Result
}

function Get-PrimaryGoogleBookFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GoogleRoot
    )

    $Preferred = @("book.epub", "book.pdf", "book.docx")
    foreach ($Name in $Preferred) {
        $Path = Join-Path $GoogleRoot $Name
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

Set-SageCurrentStep -Context $Context -Step "publish_google" -Data @{
    language = $LanguageCode
}

$BookRoot = $Context.BookRoot
$PublishRoot = Join-Path $BookRoot ("09_publish\" + $LanguageCode)
$GoogleRoot = Join-Path $PublishRoot "google"
$MetadataPath = Join-Path $PublishRoot "publish_metadata.json"
$GoogleMetadataPath = Join-Path $GoogleRoot "metadata.json"
$GooglePackagePath = Join-Path $GoogleRoot "google_play_books_package.json"
$GoogleDescriptionPath = Join-Path $GoogleRoot "google_store_description.txt"
$GoogleKeywordsPath = Join-Path $GoogleRoot "google_keywords.txt"
$GoogleChecklistPath = Join-Path $GoogleRoot "google_submission_checklist.md"

if (-not (Test-Path -LiteralPath $MetadataPath)) {
    Fail-SageStep -Context $Context -Step "publish_google" -Message "publish_metadata.json not found." -Data @{
        language = $LanguageCode
        publish_root = $PublishRoot
        metadata = $MetadataPath
    }
    Write-Error "publish_metadata.json not found: $MetadataPath"
    exit 1
}

Ensure-Directory -Path $GoogleRoot

if ((Test-Path -LiteralPath $GooglePackagePath) -and (-not $Force)) {
    Write-Host "google_play_books_package.json already exists. Use -Force to regenerate."
    exit 0
}

$PublishMetadata = Get-Content -LiteralPath $MetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$GoogleMetadata = if (Test-Path -LiteralPath $GoogleMetadataPath) {
    Get-Content -LiteralPath $GoogleMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $null
}

$GoogleKeywords = Get-GoogleKeywords -Keywords @($PublishMetadata.keywords | ForEach-Object { "$_" })
$GoogleCategories = Get-GoogleCategories -BookType "$($PublishMetadata.book_type)" -Audience "$($PublishMetadata.audience)" -CoreThesis "$($PublishMetadata.core_thesis)"
$BookFilePath = Get-PrimaryGoogleBookFile -GoogleRoot $GoogleRoot
$CoverPath = Join-Path $GoogleRoot "cover.png"
if (-not (Test-Path -LiteralPath $CoverPath)) {
    $CoverPath = Join-Path $GoogleRoot "cover.jpg"
}
if (-not (Test-Path -LiteralPath $CoverPath)) {
    $CoverPath = Join-Path $GoogleRoot "cover.jpeg"
}

$GooglePackage = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    platform = "google_play_books"
    language = $LanguageCode
    package_ready = $true
    submission_type = "ebook"
    book_details = [ordered]@{
        title = "$($PublishMetadata.title)"
        subtitle = "$($PublishMetadata.subtitle)"
        author = "$($PublishMetadata.author)"
        description = "$($PublishMetadata.long_description)"
        short_description = "$($PublishMetadata.short_description)"
        keywords = @($GoogleKeywords)
        categories = @($GoogleCategories)
        language = "$($PublishMetadata.language_name)"
        publisher = "$($PublishMetadata.publisher)"
        imprint = "$($PublishMetadata.imprint)"
        publication_date = "$($PublishMetadata.publication_date)"
        rights = "$($PublishMetadata.rights)"
        territory = "$($PublishMetadata.territory)"
        edition_type = "$($PublishMetadata.edition_type)"
        author_bio = "$($PublishMetadata.author_bio)"
    }
    upload_assets = [ordered]@{
        book = if ($BookFilePath) { Get-RelativePathSafe -BasePath $BookRoot -TargetPath $BookFilePath } else { $null }
        cover = if (Test-Path -LiteralPath $CoverPath) { Get-RelativePathSafe -BasePath $BookRoot -TargetPath $CoverPath } else { $null }
        metadata = if (Test-Path -LiteralPath $GoogleMetadataPath) { Get-RelativePathSafe -BasePath $BookRoot -TargetPath $GoogleMetadataPath } else { $null }
    }
    quality_checks = [ordered]@{
        has_title = (-not [string]::IsNullOrWhiteSpace("$($PublishMetadata.title)"))
        has_author = (-not [string]::IsNullOrWhiteSpace("$($PublishMetadata.author)"))
        has_description = (-not [string]::IsNullOrWhiteSpace("$($PublishMetadata.long_description)"))
        has_cover = (Test-Path -LiteralPath $CoverPath)
        has_book_file = ($null -ne $BookFilePath)
        keyword_count = $GoogleKeywords.Count
        category_count = $GoogleCategories.Count
    }
    manual_fields = [ordered]@{
        partner_account = ""
        isbn = ""
        pricing_model = ""
        sales_regions = "Set manually in Google Play Books Partner Center."
        preview_percentage = ""
        tax_profile = ""
    }
}

if (-not $GooglePackage.quality_checks.has_cover -or -not $GooglePackage.quality_checks.has_book_file) {
    $GooglePackage.package_ready = $false
}

$GooglePackage | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $GooglePackagePath -Encoding UTF8

$DescriptionText = @(
    "$($PublishMetadata.title)",
    "",
    "$($PublishMetadata.long_description)"
) -join "`r`n"
Write-TextUtf8 -Path $GoogleDescriptionPath -Content $DescriptionText

$KeywordLines = @()
for ($i = 0; $i -lt $GoogleKeywords.Count; $i++) {
    $KeywordLines += ("Keyword {0}: {1}" -f ($i + 1), $GoogleKeywords[$i])
}
Write-TextUtf8 -Path $GoogleKeywordsPath -Content ($KeywordLines -join "`r`n")

$ChecklistLines = @()
$ChecklistLines += "# Google Play Books Submission Checklist"
$ChecklistLines += ""
$ChecklistLines += "- Title: $($PublishMetadata.title)"
$ChecklistLines += "- Subtitle: $($PublishMetadata.subtitle)"
$ChecklistLines += "- Author: $($PublishMetadata.author)"
$ChecklistLines += "- Language: $($PublishMetadata.language_name)"
$ChecklistLines += "- Submission type: ebook"
$ChecklistLines += ""
$ChecklistLines += "## Upload Assets"
$ChecklistLines += ""
$ChecklistLines += "- Book: $($GooglePackage.upload_assets.book)"
$ChecklistLines += "- Cover: $($GooglePackage.upload_assets.cover)"
$ChecklistLines += "- Metadata: $($GooglePackage.upload_assets.metadata)"
$ChecklistLines += ""
$ChecklistLines += "## Store Description"
$ChecklistLines += ""
$ChecklistLines += "$($PublishMetadata.long_description)"
$ChecklistLines += ""
$ChecklistLines += "## Suggested Keywords"
$ChecklistLines += ""
$GoogleKeywords | ForEach-Object { $ChecklistLines += "- $_" }
$ChecklistLines += ""
$ChecklistLines += "## Suggested Categories"
$ChecklistLines += ""
$GoogleCategories | ForEach-Object { $ChecklistLines += "- $_" }
$ChecklistLines += ""
$ChecklistLines += "## Manual Review Before Submission"
$ChecklistLines += ""
$ChecklistLines += "- Confirm EPUB or PDF passes Google Play Books ingestion"
$ChecklistLines += "- Confirm cover image is the intended storefront cover"
$ChecklistLines += "- Confirm description, keywords, and categories fit the Google storefront"
$ChecklistLines += "- Confirm partner account, ISBN, pricing, regions, and preview settings"
$ChecklistLines += "- Confirm rights and publication date before publishing"

Write-TextUtf8 -Path $GoogleChecklistPath -Content ($ChecklistLines -join "`r`n")

Write-Host ""
Write-Host "09e-google completed successfully."
Write-Host ("Google package: " + $GooglePackagePath)
Write-Host ("Checklist:      " + $GoogleChecklistPath)

Complete-SageStep -Context $Context -Step "publish_google" -State "success" -Message "Google Play Books package prepared." -Data @{
    language = $LanguageCode
    google_root = $GoogleRoot
    package = $GooglePackagePath
    checklist = $GoogleChecklistPath
    keyword_count = $GoogleKeywords.Count
    category_count = $GoogleCategories.Count
    package_ready = $GooglePackage.package_ready
}
