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

Below is the book definition (SOURCE OF TRUTH):

$ObjectiveContent

Task:
Generate a complete professional table of contents.

Core Principle:
- The book definition above is the single source of truth.
- Do NOT override, reinterpret, or expand beyond it.

Binding Rules:
- Title must exactly reflect the defined book title
- Audience must align with the defined target readers
- Scope must strictly follow the defined content boundaries
- Chapter count and structure must follow the definition exactly
- Do not introduce new themes, topics, or expansions not present in the definition

Output Requirements:
- Logical progression
- Publication-level quality
- Markdown format

Heading Rules:
- Use '## ' for chapter-level headings
- Use exactly '### ' for section headings

Numbering Rules:
- Format: ### [Chapter].[Section] Title
- Example:
  ### 2.1 Concept Definition
  ### 2.2 Method Framework

Strict Constraints:
- Every section must start with '### '
- Numbering is mandatory and continuous
- Do not use bullets
- Do not use '####' or other heading levels

Consistency Rules:
- Chapter count must match the definition exactly
- Section depth must match the definition intent
- Do not add or remove chapters

Structural Constraints:

- Ensure strict logical progression between chapters (each chapter builds upon the previous one)
- Ensure strong logical isolation (each chapter has a clearly defined and non-overlapping scope)
- Avoid redundancy: no repeated explanations of the same concept across chapters
- Each concept must have a single primary location in the structure
- Later chapters may reference earlier concepts but must not redefine them

IMPORTANT:
- If all constraints are already satisfied, do not alter structure
"@
# ===== Build JSON (string) =====
$BodyObject = @{
    model = "gpt-5.2"
    input = $Prompt
}

$JsonString = $BodyObject | ConvertTo-Json -Depth 10 -Compress

# mem
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

$LogEntry | ConvertTo-Json -Depth 10 | Out-File $LogPath -Encoding utf8

Write-Output "SUCCESS: TOC generated at $TocPath"
