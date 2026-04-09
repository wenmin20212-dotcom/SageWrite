param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
$LanguageCode = $Language.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    $LanguageCode = "zh"
}
Set-SageCurrentStep -Context $Context -Step "build_pdf" -Data @{
    language = $LanguageCode
    auto_number = [bool]$AutoNumber
}

$WorkspaceRoot = $Context.WorkspaceRoot
$BookRoot = $Context.BookRoot
$OutputRoot = Join-Path $BookRoot ("04_output\" + $LanguageCode)
$BuildScriptPath = Join-Path $Context.EnginePath "05-build.ps1"
$DocxPath = Join-Path $OutputRoot "$BookName`_full.docx"
$PdfPath = Join-Path $OutputRoot "$BookName`_full.pdf"
$BackupRoot = Join-Path $OutputRoot "back"
$BackupFile = $null

function Invoke-StableDocxBuild {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetBookName,

        [switch]$EnableAutoNumber
    )

    if (!(Test-Path $ScriptPath)) {
        throw "05-build.ps1 not found: $ScriptPath"
    }

    $Args = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $ScriptPath,
        "-BookName",
        $TargetBookName,
        "-Language",
        $LanguageCode
    )

    if ($EnableAutoNumber) {
        $Args += "-AutoNumber"
    }

    & powershell.exe @Args
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        throw "05-build.ps1 failed with exit code $ExitCode."
    }
}

function Convert-DocxToPdf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDocx,

        [Parameter(Mandatory = $true)]
        [string]$TargetPdf
    )

    $Word = $null
    $Document = $null
    try {
        $Word = New-Object -ComObject Word.Application
        $Word.Visible = $false
        $Word.DisplayAlerts = 0

        $Document = $Word.Documents.Open($SourceDocx, $false, $true)
        $wdFormatPDF = 17
        $Document.SaveAs([ref]$TargetPdf, [ref]$wdFormatPDF)
    }
    finally {
        if ($null -ne $Document) {
            try {
                $wdDoNotSaveChanges = 0
                $Document.Close([ref]$wdDoNotSaveChanges)
            }
            catch {
            }
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($Document)
        }

        if ($null -ne $Word) {
            try {
                $Word.Quit()
            }
            catch {
            }
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($Word)
        }

        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

if (!(Test-Path $WorkspaceRoot)) {
    Fail-SageStep -Context $Context -Step "build_pdf" -Message "Workspace not found." -Data @{ workspace = $WorkspaceRoot; language = $LanguageCode }
    Write-Error "Workspace not found: $WorkspaceRoot"
    exit 1
}

if (!(Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

Write-Host "Building latest DOCX first..."

$UsingExistingDocx = $false
try {
    Invoke-StableDocxBuild -ScriptPath $BuildScriptPath -TargetBookName $BookName -EnableAutoNumber:$AutoNumber
}
catch {
    if ((Test-Path $DocxPath) -and $_.Exception.Message -match "failed with exit code 1") {
        Write-Host ""
        Write-Host "DOCX rebuild is currently blocked. Falling back to the existing DOCX file:"
        Write-Host $DocxPath
        $UsingExistingDocx = $true
    }
    else {
        Fail-SageStep -Context $Context -Step "build_pdf" -Message "DOCX build prerequisite failed." -Data @{
            docx_output = $DocxPath
            error = $_.Exception.Message
            language = $LanguageCode
        }
        Write-Error "DOCX build prerequisite failed: $($_.Exception.Message)"
        exit 1
    }
}

if (!(Test-Path $DocxPath)) {
    Fail-SageStep -Context $Context -Step "build_pdf" -Message "DOCX output not found after build." -Data @{
        docx_output = $DocxPath
        language = $LanguageCode
    }
    Write-Error "DOCX output not found after build: $DocxPath"
    exit 1
}

if (Test-Path $PdfPath) {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupFile = Join-Path $BackupRoot ("{0}_{1}{2}" -f $BookName, $Stamp, [System.IO.Path]::GetExtension($PdfPath))
    Copy-Item -LiteralPath $PdfPath -Destination $BackupFile -Force
    Write-Host ""
    Write-Host "Backed up existing output to:"
    Write-Host $BackupFile

    try {
        Remove-Item -LiteralPath $PdfPath -Force -ErrorAction Stop
    }
    catch {
        Fail-SageStep -Context $Context -Step "build_pdf" -Message "Existing PDF file is locked." -Data @{
            output = $PdfPath
            backup_output = $BackupFile
            error = $_.Exception.Message
            language = $LanguageCode
        }
        Write-Error "Existing PDF file is locked. Please close the PDF document and try again: $PdfPath"
        exit 1
    }
}

try {
    Write-Host ""
    Write-Host "Converting DOCX to PDF via Microsoft Word..."
    Convert-DocxToPdf -SourceDocx $DocxPath -TargetPdf $PdfPath

    if (!(Test-Path $PdfPath)) {
        throw "PDF was not created."
    }

    Write-Host ""
    Write-Host "PDF build completed successfully:"
    Write-Host $PdfPath
}
catch {
    Fail-SageStep -Context $Context -Step "build_pdf" -Message "PDF build failed." -Data @{
        output = $PdfPath
        source_docx = $DocxPath
        error = $_.Exception.Message
        language = $LanguageCode
    }
    Write-Error "PDF build failed: $($_.Exception.Message)"
    exit 1
}

Complete-SageStep -Context $Context -Step "build_pdf" -State "success" -Message "PDF build completed." -Data @{
    language = $LanguageCode
    output = $PdfPath
    source_docx = $DocxPath
    backup_output = $BackupFile
    used_existing_docx = [bool]$UsingExistingDocx
    auto_number = [bool]$AutoNumber
}

exit 0
