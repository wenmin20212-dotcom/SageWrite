param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber,

    [string]$OutputPath
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
$ChcpPath = Join-Path $env:SystemRoot "System32\chcp.com"
if (Test-Path $ChcpPath) {
    & $ChcpPath 65001 | Out-Null
}

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
$PdfPath = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Join-Path $OutputRoot "$BookName`_full.pdf"
}
else {
    [System.IO.Path]::GetFullPath($OutputPath)
}
$CoverPath = Join-Path $BookRoot "00_intake\cover.png"
$BackupRoot = Join-Path $OutputRoot "back"
$BackupFile = $null

$CheckRoot = if ($LanguageCode -eq 'zh') { $BookRoot } else { Join-Path $BookRoot ("03_translation/" + $LanguageCode) }
$PowerShellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
& $PowerShellPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '04F.ps1') -BookName $BookName -BookRoot $CheckRoot -Mode Verify
if ($LASTEXITCODE -ne 0) { throw 'PDF blocked by format preflight. Run 04F.ps1 first.' }

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

    $PowerShellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    & $PowerShellPath @Args
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
        [string]$TargetPdf,

        [string]$CoverImage
    )

    $Word = $null
    $Document = $null
    try {
        $Word = New-Object -ComObject Word.Application
        $Word.Visible = $false
        $Word.DisplayAlerts = 0

        $Document = $Word.Documents.Open($SourceDocx, $false, $true)
        if (-not [string]::IsNullOrWhiteSpace($CoverImage) -and (Test-Path -LiteralPath $CoverImage)) {
            $CoverRange = $Document.Range(0, 0)
            $CoverShape = $Document.InlineShapes.AddPicture($CoverImage, $false, $true, $CoverRange)
            $CoverShape.LockAspectRatio = -1

            $Section = $Document.Sections.Item(1)
            $Section.PageSetup.DifferentFirstPageHeaderFooter = -1
            $Section.Headers.Item(2).Range.Text = ""
            $Section.Footers.Item(2).Range.Text = ""
            $AvailableWidth = $Section.PageSetup.PageWidth - $Section.PageSetup.LeftMargin - $Section.PageSetup.RightMargin
            $AvailableHeight = $Section.PageSetup.PageHeight - $Section.PageSetup.TopMargin - $Section.PageSetup.BottomMargin
            if (($CoverShape.Width / $CoverShape.Height) -gt ($AvailableWidth / $AvailableHeight)) {
                $CoverShape.Width = $AvailableWidth
            }
            else {
                $CoverShape.Height = $AvailableHeight
            }

            $CoverShape.Range.ParagraphFormat.Alignment = 1
            $AfterCover = $Document.Range($CoverShape.Range.End, $CoverShape.Range.End)
            $AfterCover.InsertBreak(7)
        }
        try {
            [void]$Document.Fields.Update()
            foreach ($Toc in @($Document.TablesOfContents)) {
                [void]$Toc.Update()
            }
        }
        catch {
        }
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
    throw "DOCX rebuild failed; exporting an older DOCX is not allowed: $($_.Exception.Message)"
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
    & $PowerShellPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '04F.ps1') -BookName $BookName -BookRoot $CheckRoot -Mode Verify
    if ($LASTEXITCODE -ne 0) { throw 'Inputs changed during DOCX build; PDF export blocked.' }
    Convert-DocxToPdf -SourceDocx $DocxPath -TargetPdf $PdfPath -CoverImage $CoverPath

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
