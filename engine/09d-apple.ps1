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

function Get-AppleCategories {
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
            "Fiction & Literature",
            "Literary Fiction"
        )
    }

    if ($Combined -match "教育|教材|teaching|education") {
        return @(
            "Education",
            "Professional & Technical"
        )
    }

    if ($Combined -match "AI|人工智能|智能|technology|digital") {
        return @(
            "Computers & Internet",
            "Professional & Technical"
        )
    }

    return @(
        "Nonfiction",
        "Professional & Technical"
    )
}

function Get-AppleKeywords {
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
        if ($Result.Count -ge 10) {
            break
        }
    }
    return $Result
}

function Get-PrimaryEpubFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppleRoot
    )

    $Preferred = @("book.epub", "book.pdf", "book.docx")
    foreach ($Name in $Preferred) {
        $Path = Join-Path $AppleRoot $Name
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

Set-SageCurrentStep -Context $Context -Step "publish_apple" -Data @{
    language = $LanguageCode
}

$BookRoot = $Context.BookRoot
$PublishRoot = Join-Path $BookRoot ("09_publish\" + $LanguageCode)
$AppleRoot = Join-Path $PublishRoot "apple"
$MetadataPath = Join-Path $PublishRoot "publish_metadata.json"
$AppleMetadataPath = Join-Path $AppleRoot "metadata.json"
$ApplePackagePath = Join-Path $AppleRoot "apple_books_package.json"
$AppleDescriptionPath = Join-Path $AppleRoot "apple_store_description.txt"
$AppleKeywordsPath = Join-Path $AppleRoot "apple_keywords.txt"
$AppleChecklistPath = Join-Path $AppleRoot "apple_submission_checklist.md"

if (-not (Test-Path -LiteralPath $MetadataPath)) {
    Fail-SageStep -Context $Context -Step "publish_apple" -Message "publish_metadata.json not found." -Data @{
        language = $LanguageCode
        publish_root = $PublishRoot
        metadata = $MetadataPath
    }
    Write-Error "publish_metadata.json not found: $MetadataPath"
    exit 1
}

Ensure-Directory -Path $AppleRoot

if ((Test-Path -LiteralPath $ApplePackagePath) -and (-not $Force)) {
    Write-Host "apple_books_package.json already exists. Use -Force to regenerate."
    exit 0
}

$PublishMetadata = Get-Content -LiteralPath $MetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$AppleMetadata = if (Test-Path -LiteralPath $AppleMetadataPath) {
    Get-Content -LiteralPath $AppleMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $null
}

$AppleKeywords = Get-AppleKeywords -Keywords @($PublishMetadata.keywords | ForEach-Object { "$_" })
$AppleCategories = Get-AppleCategories -BookType "$($PublishMetadata.book_type)" -Audience "$($PublishMetadata.audience)" -CoreThesis "$($PublishMetadata.core_thesis)"
$ManuscriptPath = Get-PrimaryEpubFile -AppleRoot $AppleRoot
$CoverPath = Join-Path $AppleRoot "cover.png"
if (-not (Test-Path -LiteralPath $CoverPath)) {
    $CoverPath = Join-Path $AppleRoot "cover.jpg"
}
if (-not (Test-Path -LiteralPath $CoverPath)) {
    $CoverPath = Join-Path $AppleRoot "cover.jpeg"
}

$ApplePackage = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    platform = "apple_books"
    language = $LanguageCode
    package_ready = $true
    submission_type = "ebook"
    book_details = [ordered]@{
        title = "$($PublishMetadata.title)"
        subtitle = "$($PublishMetadata.subtitle)"
        author = "$($PublishMetadata.author)"
        store_description = "$($PublishMetadata.long_description)"
        short_description = "$($PublishMetadata.short_description)"
        keywords = @($AppleKeywords)
        categories = @($AppleCategories)
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
        book = if ($ManuscriptPath) { Get-RelativePathSafe -BasePath $BookRoot -TargetPath $ManuscriptPath } else { $null }
        cover = if (Test-Path -LiteralPath $CoverPath) { Get-RelativePathSafe -BasePath $BookRoot -TargetPath $CoverPath } else { $null }
        metadata = if (Test-Path -LiteralPath $AppleMetadataPath) { Get-RelativePathSafe -BasePath $BookRoot -TargetPath $AppleMetadataPath } else { $null }
    }
    quality_checks = [ordered]@{
        has_title = (-not [string]::IsNullOrWhiteSpace("$($PublishMetadata.title)"))
        has_author = (-not [string]::IsNullOrWhiteSpace("$($PublishMetadata.author)"))
        has_store_description = (-not [string]::IsNullOrWhiteSpace("$($PublishMetadata.long_description)"))
        has_cover = (Test-Path -LiteralPath $CoverPath)
        has_book_file = ($null -ne $ManuscriptPath)
        keyword_count = $AppleKeywords.Count
        category_count = $AppleCategories.Count
    }
    manual_fields = [ordered]@{
        apple_books_vendor_id = ""
        isbn = ""
        preorder_enabled = "Decide manually in Apple Books."
        pricing_tier = ""
        regions = "Set manually in Apple Books Connect."
        audience_rating = ""
    }
}

if (-not $ApplePackage.quality_checks.has_cover -or -not $ApplePackage.quality_checks.has_book_file) {
    $ApplePackage.package_ready = $false
}

$ApplePackage | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ApplePackagePath -Encoding UTF8

$DescriptionText = @(
    "$($PublishMetadata.title)",
    "",
    "$($PublishMetadata.long_description)"
) -join "`r`n"
Write-TextUtf8 -Path $AppleDescriptionPath -Content $DescriptionText

$KeywordLines = @()
for ($i = 0; $i -lt $AppleKeywords.Count; $i++) {
    $KeywordLines += ("Keyword {0}: {1}" -f ($i + 1), $AppleKeywords[$i])
}
Write-TextUtf8 -Path $AppleKeywordsPath -Content ($KeywordLines -join "`r`n")

$ChecklistLines = @()
$ChecklistLines += "# Apple Books Submission Checklist"
$ChecklistLines += ""
$ChecklistLines += "- Title: $($PublishMetadata.title)"
$ChecklistLines += "- Subtitle: $($PublishMetadata.subtitle)"
$ChecklistLines += "- Author: $($PublishMetadata.author)"
$ChecklistLines += "- Language: $($PublishMetadata.language_name)"
$ChecklistLines += "- Submission type: ebook"
$ChecklistLines += ""
$ChecklistLines += "## Upload Assets"
$ChecklistLines += ""
$ChecklistLines += "- Book: $($ApplePackage.upload_assets.book)"
$ChecklistLines += "- Cover: $($ApplePackage.upload_assets.cover)"
$ChecklistLines += "- Metadata: $($ApplePackage.upload_assets.metadata)"
$ChecklistLines += ""
$ChecklistLines += "## Store Description"
$ChecklistLines += ""
$ChecklistLines += "$($PublishMetadata.long_description)"
$ChecklistLines += ""
$ChecklistLines += "## Suggested Keywords"
$ChecklistLines += ""
$AppleKeywords | ForEach-Object { $ChecklistLines += "- $_" }
$ChecklistLines += ""
$ChecklistLines += "## Suggested Categories"
$ChecklistLines += ""
$AppleCategories | ForEach-Object { $ChecklistLines += "- $_" }
$ChecklistLines += ""
$ChecklistLines += "## Manual Review Before Submission"
$ChecklistLines += ""
$ChecklistLines += "- Confirm EPUB passes Apple Books validation"
$ChecklistLines += "- Confirm cover image meets Apple Books storefront expectations"
$ChecklistLines += "- Confirm store description is appropriate for the Apple Books product page"
$ChecklistLines += "- Confirm vendor ID, ISBN, pricing tier, and regions in Apple Books Connect"
$ChecklistLines += "- Confirm rights and publication date before final submission"

Write-TextUtf8 -Path $AppleChecklistPath -Content ($ChecklistLines -join "`r`n")

Write-Host ""
Write-Host "09d-apple completed successfully."
Write-Host ("Apple package: " + $ApplePackagePath)
Write-Host ("Checklist:     " + $AppleChecklistPath)

Complete-SageStep -Context $Context -Step "publish_apple" -State "success" -Message "Apple Books package prepared." -Data @{
    language = $LanguageCode
    apple_root = $AppleRoot
    package = $ApplePackagePath
    checklist = $AppleChecklistPath
    keyword_count = $AppleKeywords.Count
    category_count = $AppleCategories.Count
    package_ready = $ApplePackage.package_ready
}
