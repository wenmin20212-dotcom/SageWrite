param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateRange(1, 20)]
    [int]$Variants = 4,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force,
    [switch]$SkipMockup,
    [switch]$SkipPrintSpread,

    [double]$PrintTrimWidthIn = 6.0,
    [double]$PrintTrimHeightIn = 9.0,
    [double]$PrintBleedIn = 0.125,
    [double]$PrintSpineWidthIn = 0.595,
    [int]$PrintPageCount = 264,
    [int]$PrintDpi = 300
)

. "$PSScriptRoot\08n-common.ps1"

function Invoke-NextCoverStep {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][hashtable]$Arguments
    )
    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    Assert-FileExists -Path $scriptPath -Description $ScriptName
    Write-Host ""
    Write-Host ("==== {0} ====" -f $Label)
    & $scriptPath @Arguments
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "$ScriptName failed with exit code $LASTEXITCODE"
    }
}

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots
$LogPath = Join-Path $Roots.logs "08n-cover.log"
Write-TextUtf8 -Content ("[{0}] 08n-cover started for {1} / {2}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $BookName, $Edition) -Path $LogPath

$baseArgs = @{
    BookName = $BookName
    Edition = $Edition
    Title = $Title
    Subtitle = $Subtitle
    Author = $Author
    Force = $Force
}
$modeArgs = @{
    BookName = $BookName
    Edition = $Edition
    Mode = $Mode
    Force = $Force
}

Invoke-NextCoverStep -ScriptName "08n-base-brief.ps1" -Label "08n base brief" -Arguments $baseArgs
Invoke-NextCoverStep -ScriptName "08n-base-prompt.ps1" -Label "08n base prompt" -Arguments $modeArgs
Invoke-NextCoverStep -ScriptName "08n-base-generate.ps1" -Label "08n base generate" -Arguments @{
    BookName = $BookName
    Edition = $Edition
    Variants = $Variants
    Mode = $Mode
    Force = $Force
}
Invoke-NextCoverStep -ScriptName "08n-base-review.ps1" -Label "08n base review" -Arguments $modeArgs
Invoke-NextCoverStep -ScriptName "08n-title-layout.ps1" -Label "08n title layout" -Arguments @{
    BookName = $BookName
    Edition = $Edition
    Title = $Title
    Subtitle = $Subtitle
    Author = $Author
    Mode = $Mode
    Force = $Force
}

if (($Edition -eq "print") -and (-not $SkipPrintSpread)) {
    Invoke-NextCoverStep -ScriptName "08n-print-spread.ps1" -Label "08n print spread" -Arguments @{
        BookName = $BookName
        Edition = $Edition
        PrintTrimWidthIn = $PrintTrimWidthIn
        PrintTrimHeightIn = $PrintTrimHeightIn
        PrintBleedIn = $PrintBleedIn
        PrintSpineWidthIn = $PrintSpineWidthIn
        PrintPageCount = $PrintPageCount
        PrintDpi = $PrintDpi
        Force = $Force
    }
}

if (-not $SkipMockup) {
    Invoke-NextCoverStep -ScriptName "08n-mockup.ps1" -Label "08n mockup" -Arguments $modeArgs
}

Invoke-NextCoverStep -ScriptName "08n-export.ps1" -Label "08n export" -Arguments @{
    BookName = $BookName
    Edition = $Edition
    Force = $Force
}

Add-Content -LiteralPath $LogPath -Value ("[{0}] 08n-cover completed." -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

Write-Host ""
Write-Host "08n-cover completed successfully."
Write-Host "Next cover root: $($Roots.next)"
