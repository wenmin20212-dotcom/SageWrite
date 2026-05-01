param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$SourceFile,

    [string]$InputEditFile,

    [string]$InstructionJson,

    [string]$InstructionFile,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\08n-common.ps1"

function Get-KdpFixRoots {
    param([Parameter(Mandatory = $true)][string]$BookName)

    $enginePath = $PSScriptRoot
    $sageRoot = Split-Path -Parent $enginePath
    $clawRoot = Split-Path -Parent $sageRoot
    $workspaceRoot = Join-Path $clawRoot "workspace-$BookName"
    $bookRoot = Join-Path $workspaceRoot "sagewrite\book"
    $acceptanceRoot = Join-Path $bookRoot "07_cover\kdp_acceptance"
    $workRoot = Join-Path $acceptanceRoot "fix_workbench"
    return [ordered]@{
        engine = $enginePath
        workspace = $workspaceRoot
        book = $bookRoot
        acceptance = $acceptanceRoot
        work = $workRoot
        source = Join-Path $workRoot "source"
        output = Join-Path $workRoot "output"
        reports = Join-Path $workRoot "reports"
        state = Join-Path $workRoot "workbench_state.json"
    }
}

function Get-ImageInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Magick,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $format = "%w|%h|%x|%y|%U"
    $text = & $Magick identify -format $format $Path
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick identify failed: $Path"
    }
    $parts = "$text".Split("|")
    return [ordered]@{
        path = $Path
        width = [int]$parts[0]
        height = [int]$parts[1]
        densityX = "$($parts[2])"
        densityY = "$($parts[3])"
        units = "$($parts[4])"
    }
}

function Same-ImageSize {
    param($A, $B)
    return $A.width -eq $B.width -and $A.height -eq $B.height
}

function Get-InstructionNumber {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Value) {
        throw "Instruction value is missing: $Name"
    }
    return [int][Math]::Round([double]$Value)
}

function Invoke-ImageMagickMoveRegion {
    param(
        [Parameter(Mandatory = $true)][string]$Magick,
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)]$Operation,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][int]$Index
    )

    if (-not $Operation.sourceRect -or -not $Operation.targetRect) {
        throw "move_region operation requires sourceRect and targetRect."
    }

    $SourceRect = $Operation.sourceRect
    $TargetRect = $Operation.targetRect
    $X = Get-InstructionNumber -Value $SourceRect.x -Name "sourceRect.x"
    $Y = Get-InstructionNumber -Value $SourceRect.y -Name "sourceRect.y"
    $W = Get-InstructionNumber -Value $SourceRect.w -Name "sourceRect.w"
    $H = Get-InstructionNumber -Value $SourceRect.h -Name "sourceRect.h"
    $TargetX = Get-InstructionNumber -Value $TargetRect.x -Name "targetRect.x"
    $TargetY = Get-InstructionNumber -Value $TargetRect.y -Name "targetRect.y"
    if ($W -le 0 -or $H -le 0) {
        throw "move_region operation has invalid size: ${W}x${H}"
    }

    $TempRoot = [System.IO.Path]::GetTempPath()
    $PatchPath = Join-Path $TempRoot "$TaskId-op$Index-patch.png"
    $ClearedPath = Join-Path $TempRoot "$TaskId-op$Index-cleared.png"
    $CropGeometry = "${W}x${H}+${X}+${Y}"
    & $Magick $InputPath -crop $CropGeometry +repage $PatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick crop failed for operation $Index."
    }

    $ClearSource = $true
    if ($null -ne $Operation.clearSource) {
        $ClearSource = [System.Convert]::ToBoolean($Operation.clearSource)
    }
    $Fill = if ($Operation.fillSourceWith) { "$($Operation.fillSourceWith)" } else { "#07121b" }
    if ($ClearSource) {
        $X2 = $X + $W - 1
        $Y2 = $Y + $H - 1
        & $Magick $InputPath -fill $Fill -draw "rectangle $X,$Y $X2,$Y2" $ClearedPath
        if ($LASTEXITCODE -ne 0) {
            throw "ImageMagick clear-source draw failed for operation $Index."
        }
    } else {
        & $Magick $InputPath $ClearedPath
        if ($LASTEXITCODE -ne 0) {
            throw "ImageMagick intermediate copy failed for operation $Index."
        }
    }

    & $Magick $ClearedPath $PatchPath -geometry "+$TargetX+$TargetY" -composite $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick composite failed for operation $Index."
    }

    Remove-Item -LiteralPath $PatchPath, $ClearedPath -Force -ErrorAction SilentlyContinue
    return [ordered]@{
        id = "$($Operation.id)"
        type = "move_region"
        text = "$($Operation.text)"
        source_rect = [ordered]@{ x = $X; y = $Y; w = $W; h = $H }
        target_rect = [ordered]@{ x = $TargetX; y = $TargetY; w = $W; h = $H }
        dx = $TargetX - $X
        dy = $TargetY - $Y
        clear_source = $ClearSource
        fill_source_with = $Fill
    }
}

$Roots = Get-KdpFixRoots -BookName $BookName
foreach ($key in @("acceptance", "work", "source", "output", "reports")) {
    Ensure-Directory -Path $Roots[$key]
}

$MagickCommand = Get-Command magick -ErrorAction SilentlyContinue
if (-not $MagickCommand) {
    throw "ImageMagick command 'magick' was not found. Install ImageMagick and ensure magick.exe is on PATH."
}
$Magick = $MagickCommand.Source

$State = if (Test-Path -LiteralPath $Roots.state) {
    try { Read-JsonUtf8 -Path $Roots.state } catch { $null }
} else {
    $null
}

if ([string]::IsNullOrWhiteSpace($SourceFile) -and $State -and $State.sourceFileName) {
    $SourceFile = "$($State.sourceFileName)"
}
if ([string]::IsNullOrWhiteSpace($InputEditFile) -and $State -and $State.outputFileName) {
    $InputEditFile = "$($State.outputFileName)"
}
if ([string]::IsNullOrWhiteSpace($SourceFile)) {
    throw "SourceFile is required. Click Prepare Fix Files first."
}

$SourcePath = Join-Path $Roots.source ([System.IO.Path]::GetFileName($SourceFile))
Assert-FileExists -Path $SourcePath -Description "KDP ImageMagick source image"

$CandidatePath = ""
if (-not [string]::IsNullOrWhiteSpace($InputEditFile)) {
    $CandidatePath = Join-Path $Roots.output ([System.IO.Path]::GetFileName($InputEditFile))
    if (-not (Test-Path -LiteralPath $CandidatePath)) {
        $CandidatePath = ""
    }
}

$InstructionSet = $null
$InstructionSource = ""
if (-not [string]::IsNullOrWhiteSpace($InstructionJson)) {
    $InstructionSet = $InstructionJson | ConvertFrom-Json
    $InstructionSource = "inline-json"
} elseif (-not [string]::IsNullOrWhiteSpace($InstructionFile)) {
    $InstructionPath = Join-Path $Roots.reports ([System.IO.Path]::GetFileName($InstructionFile))
    Assert-FileExists -Path $InstructionPath -Description "ImageMagick instruction JSON"
    $InstructionJson = Get-Content -LiteralPath $InstructionPath -Raw -Encoding UTF8
    $InstructionSet = $InstructionJson | ConvertFrom-Json
    $InstructionSource = $InstructionPath
} elseif ($State -and $State.imageMagickInstructions) {
    $InstructionJson = "$($State.imageMagickInstructions)"
    $InstructionSet = $InstructionJson | ConvertFrom-Json
    $InstructionSource = "workbench_state.json"
}

$Stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$TaskId = "kdp-imagemagick-$Stamp"
$OutputName = "kdp-imagemagick-output-$Stamp.png"
$OutputPath = Join-Path $Roots.output $OutputName
$ReportJsonPath = Join-Path $Roots.reports "kdp-imagemagick-run-$Stamp.json"
$ReportMdPath = Join-Path $Roots.reports "kdp-imagemagick-run-$Stamp.md"
$InstructionSavePath = Join-Path $Roots.reports "kdp-imagemagick-instructions-$Stamp.json"

if ((Test-Path -LiteralPath $OutputPath) -and (-not $Force)) {
    throw "Output already exists: $OutputPath"
}

Write-Host "KDP ImageMagick fix task started."
Write-Host "Task ID: $TaskId"
Write-Host "Called task: KDP deterministic canvas-safe image fix"
Write-Host "Called program: kdp-imagemagick-fix.ps1"
Write-Host "ImageMagick: $Magick"
Write-Host "BookName: $BookName"
Write-Host "Source image: $SourcePath"
Write-Host "Candidate edited image: $CandidatePath"
Write-Host "Output image: $OutputPath"
Write-Host "Report JSON: $ReportJsonPath"
Write-Host "Report Markdown: $ReportMdPath"
Write-Host "Instruction source: $InstructionSource"
if ($InstructionJson) {
    Write-TextUtf8 -Content $InstructionJson -Path $InstructionSavePath
    Write-Host "Instruction JSON saved: $InstructionSavePath"
}

$SourceInfo = Get-ImageInfo -Magick $Magick -Path $SourcePath
$CandidateInfo = $null
$AcceptedCandidate = $false
$Decision = ""
$BasePath = $SourcePath
$AppliedOperations = @()
$InstructionOperations = @()
if ($InstructionSet -and $InstructionSet.operations) {
    $InstructionOperations = @($InstructionSet.operations) | Where-Object { $_ -and "$($_.type)" -eq "move_region" }
}

if ($InstructionOperations.Count -gt 0) {
    $Decision = "Applied ImageMagick instruction set to source canvas: $($InstructionOperations.Count) move_region operation(s)."
} elseif ($CandidatePath) {
    $CandidateInfo = Get-ImageInfo -Magick $Magick -Path $CandidatePath
    if (Same-ImageSize -A $SourceInfo -B $CandidateInfo) {
        $AcceptedCandidate = $true
        $BasePath = $CandidatePath
        $Decision = "Candidate edit accepted because it matches the source canvas size."
    } else {
        $Decision = "Candidate edit rejected as a full-canvas replacement because its pixel size differs from the 300DPI source canvas."
    }
} else {
    $Decision = "No candidate edit image was found; source canvas was preserved."
}

Write-Host "Source size: $($SourceInfo.width) x $($SourceInfo.height)"
if ($CandidateInfo) {
    Write-Host "Candidate size: $($CandidateInfo.width) x $($CandidateInfo.height)"
}
Write-Host "Instruction operation count: $($InstructionOperations.Count)"
Write-Host "Decision: $Decision"

if ($InstructionOperations.Count -gt 0) {
    $CurrentPath = $SourcePath
    $IntermediatePaths = @()
    for ($i = 0; $i -lt $InstructionOperations.Count; $i++) {
        $NextPath = if ($i -eq ($InstructionOperations.Count - 1)) {
            Join-Path ([System.IO.Path]::GetTempPath()) "$TaskId-final-before-density.png"
        } else {
            Join-Path ([System.IO.Path]::GetTempPath()) "$TaskId-op$($i + 1)-output.png"
        }
        $AppliedOperations += Invoke-ImageMagickMoveRegion -Magick $Magick -InputPath $CurrentPath -OutputPath $NextPath -Operation $InstructionOperations[$i] -TaskId $TaskId -Index ($i + 1)
        if ($CurrentPath -ne $SourcePath) {
            $IntermediatePaths += $CurrentPath
        }
        $CurrentPath = $NextPath
    }
    & $Magick $CurrentPath -units PixelsPerInch -density 300 $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick output command failed."
    }
    $IntermediatePaths += $CurrentPath
    Remove-Item -LiteralPath $IntermediatePaths -Force -ErrorAction SilentlyContinue
} else {
    & $Magick $BasePath -units PixelsPerInch -density 300 $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick output command failed."
    }
}
$OutputInfo = Get-ImageInfo -Magick $Magick -Path $OutputPath

$EndedAt = Get-Date
$Report = [ordered]@{
    generated_at = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
    task_id = $TaskId
    book_name = $BookName
    task = "KDP deterministic canvas-safe image fix"
    script = "kdp-imagemagick-fix.ps1"
    imagemagick = $Magick
    source = $SourceInfo
    candidate = $CandidateInfo
    candidate_accepted = $AcceptedCandidate
    instruction_source = $InstructionSource
    instruction_json = $InstructionSavePath
    instruction_operation_count = $InstructionOperations.Count
    applied_operations = $AppliedOperations
    decision = $Decision
    output = $OutputInfo
    output_image = $OutputPath
}
Write-JsonUtf8 -Data $Report -Path $ReportJsonPath -Depth 60

$NextState = [ordered]@{
    updatedAt = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
    taskId = $TaskId
    sourceFileName = [System.IO.Path]::GetFileName($SourcePath)
    sourcePath = $SourcePath
    outputFileName = $OutputName
    outputPath = $OutputPath
    latestImageMagickReportPath = $ReportJsonPath
    latestImageMagickInstructionPath = $InstructionSavePath
    imageMagickInstructions = $InstructionJson
    latestRun = [ordered]@{
        taskId = $TaskId
        program = "kdp-imagemagick-fix.ps1"
        candidateAccepted = $AcceptedCandidate
        instructionOperationCount = $InstructionOperations.Count
        decision = $Decision
    }
}
if ($State) {
    foreach ($property in $State.PSObject.Properties) {
        if (-not $NextState.Contains($property.Name)) {
            $NextState[$property.Name] = $property.Value
        }
    }
}
Write-JsonUtf8 -Data $NextState -Path $Roots.state -Depth 60

$ReportLines = @(
    "# KDP ImageMagick Fix Report",
    "",
    "- Generated at: $($Report.generated_at)",
    "- Task ID: $TaskId",
    "- Program: kdp-imagemagick-fix.ps1",
    "- ImageMagick: $Magick",
    "- Source: $SourcePath",
    "- Candidate: $CandidatePath",
    "- Output: $OutputPath",
    "- Instruction source: $InstructionSource",
    "- Instruction JSON: $InstructionSavePath",
    "- Instruction operations: $($InstructionOperations.Count)",
    "- Source size: $($SourceInfo.width) x $($SourceInfo.height)",
    $(if ($CandidateInfo) { "- Candidate size: $($CandidateInfo.width) x $($CandidateInfo.height)" } else { "- Candidate size: none" }),
    "- Output size: $($OutputInfo.width) x $($OutputInfo.height)",
    "- Decision: $Decision"
)
Write-TextUtf8 -Content ($ReportLines -join "`r`n") -Path $ReportMdPath

Write-Host ""
Write-Host "KDP ImageMagick fix completed."
Write-Host "Task ID: $TaskId"
Write-Host "Output size: $($OutputInfo.width) x $($OutputInfo.height)"
Write-Host "Output density: $($OutputInfo.densityX) x $($OutputInfo.densityY) $($OutputInfo.units)"
Write-Host "Instruction operations applied: $($InstructionOperations.Count)"
Write-Host "Candidate accepted: $AcceptedCandidate"
Write-Host "Decision: $Decision"
