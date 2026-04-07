param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [switch]$AutoNumber
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "build" -Data @{
    auto_number = [bool]$AutoNumber
}

$WorkspaceRoot = $Context.WorkspaceRoot
$BookRoot = $Context.BookRoot
$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
$ChapterRoot = Join-Path $BookRoot "02_chapters"
$OutputRoot = Join-Path $BookRoot "04_output"
$LogRoot = $Context.LogRoot
$BuildTempRoot = Join-Path $LogRoot "_build_tmp"

function Get-FrontMatterValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
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

    return $ValueMatch.Groups[1].Value.Trim().Trim('"')
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

function Save-XmlUtf8 {
    param(
        [Parameter(Mandatory=$true)]
        [xml]$Document,

        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $Settings = New-Object System.Xml.XmlWriterSettings
    $Settings.Encoding = $Utf8NoBom
    $Settings.Indent = $false
    $Settings.OmitXmlDeclaration = $false

    $Writer = [System.Xml.XmlWriter]::Create($Path, $Settings)
    try {
        $Document.Save($Writer)
    }
    finally {
        $Writer.Dispose()
    }
}

function Update-DocxFormatting {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DocxPath,

        [Parameter(Mandatory=$true)]
        [string]$TempRoot
    )

    if (!(Test-Path $DocxPath)) {
        throw "Output document not found for style update."
    }

    $ExtractRoot = Join-Path $TempRoot "docx_style_patch"
    if (Test-Path $ExtractRoot) {
        Remove-Item $ExtractRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $ExtractRoot -Force | Out-Null

    [System.IO.Compression.ZipFile]::ExtractToDirectory($DocxPath, $ExtractRoot)

    $StylesPath = Join-Path $ExtractRoot "word\styles.xml"
    $SettingsPath = Join-Path $ExtractRoot "word\settings.xml"
    if (!(Test-Path -LiteralPath $StylesPath)) {
        throw "word/styles.xml not found in generated document."
    }
    if (!(Test-Path -LiteralPath $SettingsPath)) {
        throw "word/settings.xml not found in generated document."
    }

    [xml]$StylesDoc = Get-Content -LiteralPath $StylesPath
    $Ns = New-Object System.Xml.XmlNamespaceManager($StylesDoc.NameTable)
    $Ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")

    $Heading1Node = $StylesDoc.SelectSingleNode("//w:style[@w:styleId='Heading1']", $Ns)
    if ($null -eq $Heading1Node) {
        throw "Heading1 style not found in generated document."
    }

    $PPrNode = $Heading1Node.SelectSingleNode("w:pPr", $Ns)
    if ($null -eq $PPrNode) {
        $PPrNode = $StylesDoc.CreateElement("w", "pPr", $Ns.LookupNamespace("w"))
        [void]$Heading1Node.PrependChild($PPrNode)
    }

    if ($null -eq $PPrNode.SelectSingleNode("w:pageBreakBefore", $Ns)) {
        $PageBreakNode = $StylesDoc.CreateElement("w", "pageBreakBefore", $Ns.LookupNamespace("w"))
        [void]$PPrNode.AppendChild($PageBreakNode)
    }

    $JcNode = $PPrNode.SelectSingleNode("w:jc", $Ns)
    if ($null -eq $JcNode) {
        $JcNode = $StylesDoc.CreateElement("w", "jc", $Ns.LookupNamespace("w"))
        [void]$PPrNode.AppendChild($JcNode)
    }
    [void]$JcNode.SetAttribute("val", $Ns.LookupNamespace("w"), "center")

    Save-XmlUtf8 -Document $StylesDoc -Path $StylesPath

    [xml]$SettingsDoc = Get-Content -LiteralPath $SettingsPath
    $SettingsNs = New-Object System.Xml.XmlNamespaceManager($SettingsDoc.NameTable)
    $SettingsNs.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")

    $SettingsRoot = $SettingsDoc.SelectSingleNode("/w:settings", $SettingsNs)
    if ($null -eq $SettingsRoot) {
        throw "settings root node not found in generated document."
    }

    $UpdateFieldsNode = $SettingsRoot.SelectSingleNode("w:updateFields", $SettingsNs)
    if ($null -eq $UpdateFieldsNode) {
        $UpdateFieldsNode = $SettingsDoc.CreateElement("w", "updateFields", $SettingsNs.LookupNamespace("w"))
        [void]$SettingsRoot.AppendChild($UpdateFieldsNode)
    }
    [void]$UpdateFieldsNode.SetAttribute("val", $SettingsNs.LookupNamespace("w"), "true")

    Save-XmlUtf8 -Document $SettingsDoc -Path $SettingsPath

    Remove-Item -Path $DocxPath -Force -ErrorAction Stop
    [System.IO.Compression.ZipFile]::CreateFromDirectory($ExtractRoot, $DocxPath)
}

if (!(Test-Path $WorkspaceRoot)) {
    Fail-SageStep -Context $Context -Step "build" -Message "Workspace not found." -Data @{ workspace = $WorkspaceRoot }
    Write-Error "Workspace not found: $WorkspaceRoot"
    exit 1
}

if (!(Test-Path $ChapterRoot)) {
    Fail-SageStep -Context $Context -Step "build" -Message "Chapter folder not found." -Data @{ chapter_root = $ChapterRoot }
    Write-Error "Chapter folder not found: $ChapterRoot"
    exit 1
}

if (!(Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

if (!(Get-Command pandoc -ErrorAction SilentlyContinue)) {
    Fail-SageStep -Context $Context -Step "build" -Message "Pandoc not found." -Data @{}
    Write-Error "Pandoc not found."
    exit 1
}

$mdFiles = Get-ChildItem $ChapterRoot -Filter *.md |
    Where-Object { $_.Name -notmatch "^_" } |
    Sort-Object {
        if ($_.BaseName -match "^\d+") {
            [int]$matches[0]
        }
        else {
            9999
        }
    }

if ($mdFiles.Count -eq 0) {
    Fail-SageStep -Context $Context -Step "build" -Message "No markdown files found." -Data @{ chapter_root = $ChapterRoot }
    Write-Error "No markdown files found."
    exit 1
}

Write-Host "Found $($mdFiles.Count) chapter files."
Write-Host ""

foreach ($file in $mdFiles) {
    Write-Host "Adding: $($file.Name)"
}

$DocumentTitle = $BookName
if (Test-Path $ObjectivePath) {
    $ObjectiveRaw = Get-Content -LiteralPath $ObjectivePath -Raw
    $ObjectiveTitle = Get-FrontMatterValue -Content $ObjectiveRaw -Key "title"
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveTitle)) {
        $DocumentTitle = $ObjectiveTitle
    }
}

if (Test-Path $BuildTempRoot) {
    Remove-Item $BuildTempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $BuildTempRoot -Force | Out-Null

$BuildFiles = @()
foreach ($file in $mdFiles) {
    $Raw = Get-Content -LiteralPath $file.FullName -Raw
    $Body = Get-MarkdownBodyText -Content $Raw
    $TempPath = Join-Path $BuildTempRoot $file.Name
    Set-Content -LiteralPath $TempPath -Encoding utf8 -Value $Body
    $BuildFiles += $TempPath
}

$MetaFile = Join-Path $ChapterRoot "_metadata.yaml"

@"
title: "$DocumentTitle"
author: "Generated by SageWrite"
date: "$(Get-Date -Format yyyy-MM-dd)"
"@ | Set-Content $MetaFile -Encoding utf8

$OutputFile = Join-Path $OutputRoot "$BookName`_full.docx"
$BackupRoot = Join-Path $OutputRoot "back"
$BackupFile = $null

if (Test-Path $OutputFile) {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupFile = Join-Path $BackupRoot ("{0}_{1}{2}" -f $BookName, $Stamp, [System.IO.Path]::GetExtension($OutputFile))
    Copy-Item -LiteralPath $OutputFile -Destination $BackupFile -Force
    Write-Host ""
    Write-Host "Backed up existing output to:"
    Write-Host $BackupFile

    try {
        Remove-Item -LiteralPath $OutputFile -Force -ErrorAction Stop
    }
    catch {
        Fail-SageStep -Context $Context -Step "build" -Message "Existing output file is locked." -Data @{
            output = $OutputFile
            backup_output = $BackupFile
            error = $_.Exception.Message
        }
        Write-Error "Existing output file is locked. Please close the Word document and try again: $OutputFile"
        exit 1
    }
}

$PandocArgs = @()
$PandocArgs += $BuildFiles
$PandocArgs += "--metadata-file=$MetaFile"
$PandocArgs += "-o"
$PandocArgs += $OutputFile
$PandocArgs += "--toc"
$PandocArgs += "--standalone"

if ($AutoNumber) {
    Write-Host ""
    Write-Host "Auto numbering enabled."
    $PandocArgs += "--number-sections"
}
else {
    Write-Host ""
    Write-Host "Auto numbering disabled."
}

try {
    & pandoc @PandocArgs
    $PandocExitCode = $LASTEXITCODE

    if ($PandocExitCode -ne 0) {
        throw "Pandoc exited with code $PandocExitCode."
    }

    if (!(Test-Path $OutputFile)) {
        throw "Pandoc build failed."
    }

    Update-DocxFormatting -DocxPath $OutputFile -TempRoot $BuildTempRoot

    Write-Host ""
    Write-Host "Build completed successfully:"
    Write-Host $OutputFile
}
catch {
    Fail-SageStep -Context $Context -Step "build" -Message "Build failed." -Data @{
        output = $OutputFile
        error = $_.Exception.Message
    }
    Write-Error "Build failed: $_"
    exit 1
}
finally {
    Remove-Item $MetaFile -ErrorAction SilentlyContinue
    Remove-Item $BuildTempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-SageStep -Context $Context -Step "build" -State "success" -Message "Document build completed." -Data @{
    output = $OutputFile
    backup_output = $BackupFile
    chapter_count = $mdFiles.Count
    document_title = $DocumentTitle
    auto_number = [bool]$AutoNumber
}
