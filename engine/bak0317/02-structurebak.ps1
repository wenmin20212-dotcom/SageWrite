param(
    [Parameter(Mandatory=$true)]
    [string]$BookName
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Path Resolve =====
$EnginePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot   = Split-Path -Parent $EnginePath
$ClawRoot   = Split-Path -Parent $SageRoot

$WorkspaceRoot = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot = Join-Path $WorkspaceRoot "sagewrite\book"

$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
$TocPath       = Join-Path $BookRoot "01_outline\toc.md"
$LogPath       = Join-Path $BookRoot "logs\run_history.json"

# ===== Validate =====
if (!(Test-Path $ObjectivePath)) {
    Write-Output "ERROR: objective.md not found."
    exit
}

if (-not $env:OPENAI_API_KEY) {
    Write-Output "ERROR: OPENAI_API_KEY not set."
    exit
}

# ===== Read Objective =====
$ObjectiveContent = Get-Content $ObjectivePath -Raw

# ===== 🔥 核心 Prompt（已修正） =====
$Prompt = @"
You are a professional academic book architect.

Below is the book definition:

$ObjectiveContent

Generate a complete table of contents.

STRICT FORMAT REQUIREMENTS:

## Chapter X: Title
### X.1 Subtitle
### X.2 Subtitle
### X.3 Subtitle

RULES:
- MUST use "##" for chapters
- MUST use "###" for sections
- MUST NOT use plain numbering like "1.1" without ###
- MUST NOT use bullet points
- MUST NOT use lists
- MUST NOT skip levels
- Output ONLY markdown headings

CONTENT REQUIREMENTS:
- 10 to 20 chapters
- Each chapter has 3 to 6 sections
- Logical progression
- Professional academic style
"@

# ===== JSON =====
$BodyObject = @{
    model = "gpt-4o-mini"
    input = $Prompt
}

$JsonString = $BodyObject | ConvertTo-Json -Depth 10 -Compress
$Utf8Bytes  = [System.Text.Encoding]::UTF8.GetBytes($JsonString)

# ===== Call API =====
try {
    $Response = Invoke-RestMethod `
        -Uri "https://api.openai.com/v1/responses" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $env:OPENAI_API_KEY"
            "Content-Type"  = "application/json; charset=utf-8"
        } `
        -Body $Utf8Bytes
}
catch {
    Write-Output "ERROR: OpenAI request failed."
    Write-Output $_
    exit
}

# ===== Extract =====
if (-not $Response.output) {
    Write-Output "ERROR: Invalid API response."
    exit
}

$TocContent = $Response.output[0].content[0].text

if (-not $TocContent) {
    Write-Output "ERROR: No content returned."
    exit
}

# ===== Write toc.md =====
@"
---
file_role: toc
layer: structure
generated_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
---

# Table of Contents

$TocContent
"@ | Out-File $TocPath -Encoding utf8

# ===== Log =====
$LogEntry = @{
    step = "structure"
    time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

$ExistingLog = @()
if (Test-Path $LogPath) {
    $ExistingLog = Get-Content $LogPath -Raw | ConvertFrom-Json
}

$UpdatedLog = $ExistingLog + $LogEntry
$UpdatedLog | ConvertTo-Json -Depth 10 | Out-File $LogPath -Encoding utf8

Write-Output "SUCCESS: TOC generated with strict structure."