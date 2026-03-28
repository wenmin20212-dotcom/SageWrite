param(
    [Parameter(Mandatory=$true)]
    [string]$BookName
)

# ===== UTF-8 Console =====
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Resolve .openclaw root =====
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

# ===== Read objective =====
$ObjectiveContent = Get-Content $ObjectivePath -Raw

# ===== Prompt =====
$Prompt = @"
You are a professional academic book architect.

Below is the book definition:

$ObjectiveContent

Generate a complete professional table of contents.

Requirements:
- 10 to 20 chapters
- Each chapter has 3 to 6 sections
- Logical progression
- Suitable for publication
- Markdown format
"@

# ===== Build JSON (string) =====
$BodyObject = @{
    model = "gpt-4o-mini"
    input = $Prompt
}

$JsonString = $BodyObject | ConvertTo-Json -Depth 10 -Compress

# 🔥 强制 UTF-8 字节编码
$Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonString)

# ===== Call OpenAI =====
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

Write-Output "SUCCESS: TOC generated at $TocPath"