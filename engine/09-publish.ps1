param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [ValidateSet("all", "amazon", "apple", "google")]
    [string]$Platform = "all",

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

function Copy-IfExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (Test-Path -LiteralPath $SourcePath) {
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
        return $true
    }

    return $false
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

function Invoke-PublishModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$BookName,

        [Parameter(Mandatory = $true)]
        [string]$LanguageCode,

        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Publish module not found: $ScriptPath"
    }

    $Args = @{
        BookName = $BookName
        Language = $LanguageCode
    }
    if ($Force) {
        $Args.Force = $true
    }

    & $ScriptPath @Args
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "Publish module failed with exit code $LASTEXITCODE"
    }
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context

$LanguageCode = $Language.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    $LanguageCode = "zh"
}

Set-SageCurrentStep -Context $Context -Step "publish" -Data @{
    language = $LanguageCode
    platform = $Platform
}

$BookRoot = $Context.BookRoot
$PublishRoot = Join-Path $BookRoot ("09_publish\" + $LanguageCode)
$AssetsPath = Join-Path $PublishRoot "publish_assets.json"
$MetadataJsonPath = Join-Path $PublishRoot "publish_metadata.json"
$MetadataMdPath = Join-Path $PublishRoot "publish_metadata.md"
$ManifestPath = Join-Path $PublishRoot "publish_manifest.json"
$ReportPath = Join-Path $PublishRoot "publish_report.md"
$CollectScriptPath = Join-Path $Context.EnginePath "09a-collect.ps1"
$MetadataScriptPath = Join-Path $Context.EnginePath "09b-metadata.ps1"
$AmazonScriptPath = Join-Path $Context.EnginePath "09c-amazon.ps1"
$AppleScriptPath = Join-Path $Context.EnginePath "09d-apple.ps1"
$GoogleScriptPath = Join-Path $Context.EnginePath "09e-google.ps1"
$Platforms = if ($Platform -eq "all") { @("amazon", "apple", "google") } else { @($Platform) }

if (-not (Test-Path -LiteralPath $BookRoot)) {
    Fail-SageStep -Context $Context -Step "publish" -Message "Book root not found." -Data @{
        book_root = $BookRoot
        language = $LanguageCode
    }
    Write-Error "Book root not found: $BookRoot"
    exit 1
}

Ensure-Directory -Path $PublishRoot

try {
    Invoke-PublishModule -ScriptPath $CollectScriptPath -BookName $BookName -LanguageCode $LanguageCode -Force:$Force

    if (-not (Test-Path -LiteralPath $AssetsPath)) {
        throw "publish_assets.json not found after 09a-collect."
    }

    Invoke-PublishModule -ScriptPath $MetadataScriptPath -BookName $BookName -LanguageCode $LanguageCode -Force:$Force
    if (-not (Test-Path -LiteralPath $MetadataJsonPath)) {
        throw "publish_metadata.json not found after 09b-metadata."
    }

    $Assets = Get-Content -LiteralPath $AssetsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $PublishMetadata = Get-Content -LiteralPath $MetadataJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $BookInfo = $Assets.book
    $Marketing = $Assets.marketing
    $RelativeEpub = "$($Assets.files.epub)"
    $RelativePdf = "$($Assets.files.pdf)"
    $RelativeDocx = "$($Assets.files.docx)"
    $RelativeCover = "$($Assets.files.cover)"

    $AbsoluteEpub = if ($RelativeEpub) { Join-Path $BookRoot $RelativeEpub } else { $null }
    $AbsolutePdf = if ($RelativePdf) { Join-Path $BookRoot $RelativePdf } else { $null }
    $AbsoluteDocx = if ($RelativeDocx) { Join-Path $BookRoot $RelativeDocx } else { $null }
    $AbsoluteCover = if ($RelativeCover) { Join-Path $BookRoot $RelativeCover } else { $null }

    $MissingItems = @()
    if (-not $AbsoluteEpub -or -not (Test-Path -LiteralPath $AbsoluteEpub)) { $MissingItems += "EPUB" }
    if (-not $AbsoluteCover -or -not (Test-Path -LiteralPath $AbsoluteCover)) { $MissingItems += "Cover image" }
    if (-not "$($BookInfo.title)") { $MissingItems += "Title" }
    if (-not "$($BookInfo.author)") { $MissingItems += "Author" }

    $Manifest = [ordered]@{
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        book_name = $BookName
        language = $LanguageCode
        platform_scope = $Platform
        ready = ($MissingItems.Count -eq 0)
        missing_items = @($MissingItems)
        platforms = @()
    }

    foreach ($PlatformName in $Platforms) {
        $PlatformRoot = Join-Path $PublishRoot $PlatformName
        if ((Test-Path -LiteralPath $PlatformRoot) -and $Force) {
            Remove-Item -LiteralPath $PlatformRoot -Recurse -Force
        }
        Ensure-Directory -Path $PlatformRoot

        $Metadata = [ordered]@{
            platform = $PlatformName
            book_name = $BookName
            language = "$($PublishMetadata.language)"
            language_name = "$($PublishMetadata.language_name)"
            title = "$($PublishMetadata.title)"
            subtitle = "$($PublishMetadata.subtitle)"
            author = "$($PublishMetadata.author)"
            audience = "$($PublishMetadata.audience)"
            type = "$($PublishMetadata.book_type)"
            style = "$($PublishMetadata.style)"
            publisher = "$($PublishMetadata.publisher)"
            imprint = "$($PublishMetadata.imprint)"
            publication_date = "$($PublishMetadata.publication_date)"
            rights = "$($PublishMetadata.rights)"
            copyright_holder = "$($PublishMetadata.copyright_holder)"
            copyright_year = "$($PublishMetadata.copyright_year)"
            territory = "$($PublishMetadata.territory)"
            distribution_rights = "$($PublishMetadata.distribution_rights)"
            edition_type = "$($PublishMetadata.edition_type)"
            short_description = "$($PublishMetadata.short_description)"
            long_description = "$($PublishMetadata.long_description)"
            marketing_tagline = "$($PublishMetadata.marketing_tagline)"
            cover_hook = "$($PublishMetadata.cover_hook)"
            back_cover_blurb = "$($PublishMetadata.back_cover_blurb)"
            obi_copy = "$($PublishMetadata.obi_copy)"
            author_bio = "$($PublishMetadata.author_bio)"
            spine_text = "$($PublishMetadata.spine_text)"
            keywords = @($PublishMetadata.keywords | ForEach-Object { "$_" })
            categories = @($PublishMetadata.categories | ForEach-Object { "$_" })
            formats = @($PublishMetadata.formats | ForEach-Object { "$_" })
            identification = $PublishMetadata.identification
            marketing = $PublishMetadata.marketing
            rights_metadata = $PublishMetadata.rights_metadata
            discovery = $PublishMetadata.discovery
            distribution = $PublishMetadata.distribution
            source_files = [ordered]@{
                epub = $RelativeEpub
                pdf = $RelativePdf
                docx = $RelativeDocx
                cover = $RelativeCover
            }
        }

        $CopiedFiles = [ordered]@{
            epub = $null
            pdf = $null
            docx = $null
            cover = $null
        }

        if ($AbsoluteEpub) {
            $DestName = "book" + [System.IO.Path]::GetExtension($AbsoluteEpub)
            $DestPath = Join-Path $PlatformRoot $DestName
            if (Copy-IfExists -SourcePath $AbsoluteEpub -DestinationPath $DestPath) {
                $CopiedFiles.epub = $DestName
            }
        }

        if ($AbsolutePdf) {
            $DestName = "book" + [System.IO.Path]::GetExtension($AbsolutePdf)
            $DestPath = Join-Path $PlatformRoot $DestName
            if (Copy-IfExists -SourcePath $AbsolutePdf -DestinationPath $DestPath) {
                $CopiedFiles.pdf = $DestName
            }
        }

        if ($AbsoluteDocx) {
            $DestName = "book" + [System.IO.Path]::GetExtension($AbsoluteDocx)
            $DestPath = Join-Path $PlatformRoot $DestName
            if (Copy-IfExists -SourcePath $AbsoluteDocx -DestinationPath $DestPath) {
                $CopiedFiles.docx = $DestName
            }
        }

        if ($AbsoluteCover) {
            $DestName = "cover" + [System.IO.Path]::GetExtension($AbsoluteCover)
            $DestPath = Join-Path $PlatformRoot $DestName
            if (Copy-IfExists -SourcePath $AbsoluteCover -DestinationPath $DestPath) {
                $CopiedFiles.cover = $DestName
            }
        }

        $MetadataPath = Join-Path $PlatformRoot "metadata.json"
        $Metadata | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MetadataPath -Encoding UTF8

        $ReadmeLines = @(
            "SageWrite 09 Publish Package",
            "",
            "Platform: $PlatformName",
            "Language: $LanguageCode",
            "Title: $($PublishMetadata.title)",
            "Author: $($PublishMetadata.author)",
            "Publisher: $($PublishMetadata.publisher)",
            "Imprint: $($PublishMetadata.imprint)",
            "",
            "Included files:",
            "- EPUB: $($CopiedFiles.epub)",
            "- PDF: $($CopiedFiles.pdf)",
            "- DOCX: $($CopiedFiles.docx)",
            "- Cover: $($CopiedFiles.cover)",
            "",
            "Metadata file:",
            "- metadata.json",
            "",
            "Manual review checklist:",
            "- Confirm title/subtitle presentation",
            "- Confirm short and long descriptions",
            "- Confirm keywords and categories",
            "- Confirm cover image is the intended final version",
            "- Confirm platform-specific classification and pricing outside SageWrite"
        )
        Write-TextUtf8 -Path (Join-Path $PlatformRoot "README.txt") -Content ($ReadmeLines -join "`r`n")

        $Manifest.platforms += [ordered]@{
            name = $PlatformName
            folder = Get-RelativePathSafe -BasePath $BookRoot -TargetPath $PlatformRoot
            metadata = Get-RelativePathSafe -BasePath $BookRoot -TargetPath $MetadataPath
            copied_files = $CopiedFiles
        }
    }

    if ($Platforms -contains "amazon") {
        Invoke-PublishModule -ScriptPath $AmazonScriptPath -BookName $BookName -LanguageCode $LanguageCode -Force:$Force
    }

    if ($Platforms -contains "apple") {
        Invoke-PublishModule -ScriptPath $AppleScriptPath -BookName $BookName -LanguageCode $LanguageCode -Force:$Force
    }

    if ($Platforms -contains "google") {
        Invoke-PublishModule -ScriptPath $GoogleScriptPath -BookName $BookName -LanguageCode $LanguageCode -Force:$Force
    }

    $Manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

    $ReportLines = @()
    $ReportLines += "# Publish Report"
    $ReportLines += ""
    $ReportLines += "- Generated at: $($Manifest.generated_at)"
    $ReportLines += "- BookName: $BookName"
    $ReportLines += "- Language: $LanguageCode"
    $ReportLines += "- Platform scope: $Platform"
    $ReportLines += "- Ready: " + ($(if ($Manifest.ready) { "Yes" } else { "No" }))
    $ReportLines += ""
    $ReportLines += "## Book"
    $ReportLines += ""
    $ReportLines += "- Title: $($PublishMetadata.title)"
    $ReportLines += "- Subtitle: $($PublishMetadata.subtitle)"
    $ReportLines += "- Author: $($PublishMetadata.author)"
    $ReportLines += "- Type: $($PublishMetadata.book_type)"
    $ReportLines += "- Publisher: $($PublishMetadata.publisher)"
    $ReportLines += "- Imprint: $($PublishMetadata.imprint)"
    $ReportLines += "- Rights: $($PublishMetadata.rights)"
    $ReportLines += "- Edition type: $($PublishMetadata.edition_type)"
    $ReportLines += ""
    $ReportLines += "## Discovery"
    $ReportLines += ""
    $ReportLines += "- Keywords: $((@($PublishMetadata.keywords) -join ', '))"
    $ReportLines += "- Categories: $((@($PublishMetadata.categories) -join ', '))"
    $ReportLines += "- Formats: $((@($PublishMetadata.formats) -join ', '))"
    $ReportLines += ""
    $ReportLines += "## Source Assets"
    $ReportLines += ""
    $ReportLines += "- EPUB: $RelativeEpub"
    $ReportLines += "- PDF: $RelativePdf"
    $ReportLines += "- DOCX: $RelativeDocx"
    $ReportLines += "- Cover: $RelativeCover"
    $ReportLines += ""
    $ReportLines += "## Missing Items"
    if ($MissingItems.Count -gt 0) {
        $MissingItems | ForEach-Object { $ReportLines += "- $_" }
    }
    else {
        $ReportLines += "- None"
    }
    $ReportLines += ""
    $ReportLines += "## Platforms"
    $ReportLines += ""
    foreach ($PlatformEntry in $Manifest.platforms) {
        $ReportLines += "### $($PlatformEntry.name)"
        $ReportLines += "- Folder: $($PlatformEntry.folder)"
        $ReportLines += "- Metadata: $($PlatformEntry.metadata)"
        $ReportLines += "- EPUB: $($PlatformEntry.copied_files.epub)"
        $ReportLines += "- PDF: $($PlatformEntry.copied_files.pdf)"
        $ReportLines += "- DOCX: $($PlatformEntry.copied_files.docx)"
        $ReportLines += "- Cover: $($PlatformEntry.copied_files.cover)"
        $ReportLines += ""
    }

    Write-TextUtf8 -Path $ReportPath -Content ($ReportLines -join "`r`n")

    Write-Host ""
    Write-Host "09-publish completed successfully."
    Write-Host ("Manifest: " + $ManifestPath)
    Write-Host ("Report:   " + $ReportPath)

    Complete-SageStep -Context $Context -Step "publish" -State "success" -Message "Publish package prepared." -Data @{
        language = $LanguageCode
        platform = $Platform
        publish_root = $PublishRoot
        manifest = $ManifestPath
        metadata_json = $MetadataJsonPath
        metadata_md = $MetadataMdPath
        report = $ReportPath
        ready = $Manifest.ready
        missing_item_count = $MissingItems.Count
    }
}
catch {
    Fail-SageStep -Context $Context -Step "publish" -Message "Publish packaging failed." -Data @{
        language = $LanguageCode
        platform = $Platform
        publish_root = $PublishRoot
        error = $_.Exception.Message
    }
    Write-Error "09-publish failed: $($_.Exception.Message)"
    exit 1
}
