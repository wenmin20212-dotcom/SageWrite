param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [int]$Chapter,

    [switch]$All,

    [int]$StartChapter,
    [int]$EndChapter,

    [int]$MinSubsections = 3,
    [int]$MaxSubsections = 5,

    [string]$Model = "gpt-4o-mini"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Resolve paths =====
$EnginePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot   = Split-Path -Parent $EnginePath
$ClawRoot   = Split-Path -Parent $SageRoot

$WorkspaceRoot = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot      = Join-Path $WorkspaceRoot "sagewrite\book"

$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
$TocPath       = Join-Path $BookRoot "01_outline\toc.md"
$Toc2Path      = Join-Path $BookRoot "01_outline\toc2.md"

# ===== Validate =====
if (!(Test-Path $ObjectivePath)) {
    Write-Output "ERROR: objective.md not found."
    exit
}

if (!(Test-Path $TocPath)) {
    Write-Output "ERROR: toc.md not found."
    exit
}

if (-not $env:OPENAI_API_KEY) {
    Write-Output "ERROR: OPENAI_API_KEY not set."
    exit
}

# ===== OpenAI call =====
function Invoke-OpenAIResponse($Prompt) {

    $BodyObject = @{
        model = $Model
        input = $Prompt
    }

    $Json = $BodyObject | ConvertTo-Json -Depth 10 -Compress
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)

    $Response = Invoke-RestMethod `
        -Uri "https://api.openai.com/v1/responses" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $env:OPENAI_API_KEY"
            "Content-Type"  = "application/json; charset=utf-8"
        } `
        -Body $Bytes

    return $Response.output[0].content[0].text
}

# ===== Read input =====
$ObjectiveContent = Get-Content $ObjectivePath -Raw
$TocContent       = Get-Content $TocPath -Raw

$Lines = $TocContent -split "`n"

$Chapters = @()
$CurrentChapter = ""
$Sections = @()

foreach ($line in $Lines) {

    if ($line -match '^##\s+(.+)$') {

        if ($CurrentChapter -ne "") {

            $Chapters += @{
                title=$CurrentChapter
                sections=$Sections
            }

        }

        $CurrentChapter = $Matches[1]
        $Sections = @()
        continue
    }

    if ($line -match '^###\s+(.+)$') {

        $Sections += $Matches[1]

    }

}

if ($CurrentChapter -ne "") {

    $Chapters += @{
        title=$CurrentChapter
        sections=$Sections
    }

}

$ChapterCount = $Chapters.Count

# ===== Determine chapter list =====
$ChapterList = @()

if ($All) {

    for ($i=1; $i -le $ChapterCount; $i++) {

        $ChapterList += $i

    }

}
elseif ($StartChapter -and $EndChapter) {

    if ($StartChapter -lt 1 -or $EndChapter -gt $ChapterCount) {

        Write-Output "ERROR: Chapter range invalid."
        exit

    }

    for ($i=$StartChapter; $i -le $EndChapter; $i++) {

        $ChapterList += $i

    }

}
elseif ($Chapter) {

    if ($Chapter -lt 1 -or $Chapter -gt $ChapterCount) {

        Write-Output "ERROR: Invalid chapter number."
        exit

    }

    $ChapterList += $Chapter

}
else {

    Write-Output "ERROR: Specify -Chapter, -All, or -StartChapter -EndChapter."
    exit

}

# ===== Start generation =====
$OutputLines = @()
$OutputLines += "# Table of Contents"
$OutputLines += ""

foreach ($chIndex in $ChapterList) {

    $ch = $Chapters[$chIndex-1]

    Write-Output "Expanding Chapter $chIndex : $($ch.title)"

    $OutputLines += "## $($ch.title)"
    $OutputLines += ""

    $secIndex = 0

    foreach ($sec in $ch.sections) {

        $secIndex++

        $OutputLines += "### $sec"

        $Prompt = @"
You are a professional academic book architect.

Book objective:
$ObjectiveContent

Chapter:
$($ch.title)

Section:
$sec

Generate $MinSubsections to $MaxSubsections subsections.

Output only titles, one per line.
"@

        $Result = Invoke-OpenAIResponse $Prompt
        $SubLines = $Result -split "`n"

        $subIndex = 0

        foreach ($s in $SubLines) {

            if ($s.Trim() -eq "") { continue }

            $subIndex++

            $OutputLines += "#### $chIndex.$secIndex.$subIndex $($s.Trim())"

        }

        $OutputLines += ""

    }

}

$OutputLines | Out-File $Toc2Path -Encoding utf8

Write-Output "SUCCESS: toc2.md updated."