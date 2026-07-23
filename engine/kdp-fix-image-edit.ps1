param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$SourceFile,

    [string]$PromptFile,

    [string]$Prompt,

    [string]$ImageModel = "gpt-image-1.5",

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
    $workspaceParentRoot = if (-not [string]::IsNullOrWhiteSpace($env:SAGEWRITE_WORKSPACE_ROOT)) { [System.IO.Path]::GetFullPath($env:SAGEWRITE_WORKSPACE_ROOT) } else { $clawRoot }
    $workspaceRoot = Join-Path $workspaceParentRoot "workspace-$BookName"
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
        prompts = Join-Path $workRoot "prompts"
        output = Join-Path $workRoot "output"
        reports = Join-Path $workRoot "reports"
        state = Join-Path $workRoot "workbench_state.json"
    }
}

function Get-ImageMimeType {
    param([Parameter(Mandatory = $true)][string]$Path)

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".png"  { return "image/png" }
        ".jpg"  { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".webp" { return "image/webp" }
        default { throw "Unsupported image type: $Path" }
    }
}

function Get-ImageB64 {
    param($Response)

    if ($Response.data -and $Response.data.Count -gt 0 -and $Response.data[0].b64_json) {
        return "$($Response.data[0].b64_json)"
    }
    if ($Response.output -and $Response.output.Count -gt 0) {
        foreach ($item in $Response.output) {
            if ($item.result) {
                return "$($item.result)"
            }
            foreach ($content in $item.content) {
                if ($content.type -eq "output_image" -and $content.image_base64) {
                    return "$($content.image_base64)"
                }
            }
        }
    }
    return ""
}

function Get-UsageValue {
    param(
        $Usage,
        [string[]]$Names
    )

    if ($null -eq $Usage) {
        return $null
    }
    foreach ($name in $Names) {
        $property = $Usage.PSObject.Properties[$name]
        if ($property -and $null -ne $property.Value) {
            return $property.Value
        }
    }
    return $null
}

function Write-UsageReport {
    param($Usage)

    if ($null -eq $Usage) {
        Write-Host "Token usage: not returned by image edit response."
        return
    }

    $inputTokens = Get-UsageValue -Usage $Usage -Names @("input_tokens", "prompt_tokens")
    $outputTokens = Get-UsageValue -Usage $Usage -Names @("output_tokens", "completion_tokens")
    $totalTokens = Get-UsageValue -Usage $Usage -Names @("total_tokens")
    if ($null -eq $totalTokens -and $null -ne $inputTokens -and $null -ne $outputTokens) {
        $totalTokens = [int]$inputTokens + [int]$outputTokens
    }

    Write-Host "Token usage summary:"
    $inputLabel = if ($null -ne $inputTokens) { "$inputTokens" } else { "-" }
    $outputLabel = if ($null -ne $outputTokens) { "$outputTokens" } else { "-" }
    $totalLabel = if ($null -ne $totalTokens) { "$totalTokens" } else { "-" }
    Write-Host "  Input tokens:  $inputLabel"
    Write-Host "  Output tokens: $outputLabel"
    Write-Host "  Total tokens:  $totalLabel"
    Write-Host "Usage raw JSON:"
    Write-Host ($Usage | ConvertTo-Json -Depth 40 -Compress)
}

$Roots = Get-KdpFixRoots -BookName $BookName
foreach ($key in @("acceptance", "work", "source", "prompts", "output", "reports")) {
    Ensure-Directory -Path $Roots[$key]
}

$State = if (Test-Path -LiteralPath $Roots.state) {
    try { Read-JsonUtf8 -Path $Roots.state } catch { $null }
} else {
    $null
}

if ([string]::IsNullOrWhiteSpace($SourceFile) -and $State -and $State.sourceFileName) {
    $SourceFile = "$($State.sourceFileName)"
}
if ([string]::IsNullOrWhiteSpace($PromptFile) -and $State -and $State.promptFileName) {
    $PromptFile = "$($State.promptFileName)"
}
if ([string]::IsNullOrWhiteSpace($Prompt) -and $State -and $State.prompt) {
    $Prompt = "$($State.prompt)"
}
if ([string]::IsNullOrWhiteSpace($ImageModel) -and $State -and $State.model) {
    $ImageModel = "$($State.model)"
}

if ([string]::IsNullOrWhiteSpace($SourceFile)) {
    throw "SourceFile is required. Click Prepare Fix Files first."
}

$SourcePath = Join-Path $Roots.source ([System.IO.Path]::GetFileName($SourceFile))
Assert-FileExists -Path $SourcePath -Description "KDP fix source image"

if ([string]::IsNullOrWhiteSpace($Prompt) -and -not [string]::IsNullOrWhiteSpace($PromptFile)) {
    $PromptPath = Join-Path $Roots.prompts ([System.IO.Path]::GetFileName($PromptFile))
    Assert-FileExists -Path $PromptPath -Description "KDP fix prompt file"
    $Prompt = Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8
} elseif (-not [string]::IsNullOrWhiteSpace($PromptFile)) {
    $PromptPath = Join-Path $Roots.prompts ([System.IO.Path]::GetFileName($PromptFile))
} else {
    $PromptPath = ""
}

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    throw "Prompt is required."
}
if (-not $env:OPENAI_API_KEY) {
    throw "OPENAI_API_KEY not set."
}

$Stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$TaskId = "kdp-fix-$Stamp"
$OutputName = "kdp-fix-output-$Stamp.png"
$OutputPath = Join-Path $Roots.output $OutputName
$ReportJsonPath = Join-Path $Roots.reports "kdp-fix-run-$Stamp.json"
$ReportMdPath = Join-Path $Roots.reports "kdp-fix-run-$Stamp.md"

if ((Test-Path -LiteralPath $OutputPath) -and (-not $Force)) {
    throw "Output already exists: $OutputPath"
}

Write-Host "KDP fix image edit task started."
Write-Host "Task ID: $TaskId"
Write-Host "Called task: KDP cover repair image edit"
Write-Host "Called program: kdp-fix-image-edit.ps1"
Write-Host "BookName: $BookName"
Write-Host "Image model: $ImageModel"
Write-Host "Endpoint: https://api.openai.com/v1/images/edits"
Write-Host "Source image: $SourcePath"
Write-Host "Prompt file: $PromptPath"
Write-Host "Output image: $OutputPath"
Write-Host "Report JSON: $ReportJsonPath"
Write-Host "Report Markdown: $ReportMdPath"
Write-Host "Prompt length: $($Prompt.Length) characters"
Write-Host ""
Write-Host "Prompt:"
Write-Host "-----"
Write-Host $Prompt
Write-Host "-----"

Add-Type -AssemblyName System.Net.Http
$client = [System.Net.Http.HttpClient]::new()
$fileStream = $null
$form = $null
try {
    $client.Timeout = [TimeSpan]::FromMinutes(8)
    $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $env:OPENAI_API_KEY)
    $form = [System.Net.Http.MultipartFormDataContent]::new()
    $form.Add([System.Net.Http.StringContent]::new($ImageModel, [System.Text.Encoding]::UTF8), "model")
    $form.Add([System.Net.Http.StringContent]::new($Prompt, [System.Text.Encoding]::UTF8), "prompt")
    $form.Add([System.Net.Http.StringContent]::new("auto", [System.Text.Encoding]::UTF8), "size")
    $form.Add([System.Net.Http.StringContent]::new("png", [System.Text.Encoding]::UTF8), "output_format")
    $form.Add([System.Net.Http.StringContent]::new("high", [System.Text.Encoding]::UTF8), "quality")

    $fileStream = [System.IO.File]::OpenRead($SourcePath)
    $imageContent = [System.Net.Http.StreamContent]::new($fileStream)
    $imageContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse((Get-ImageMimeType -Path $SourcePath))
    $form.Add($imageContent, "image", [System.IO.Path]::GetFileName($SourcePath))

    $StartedAt = Get-Date
    Write-Host ""
    Write-Host "Calling OpenAI Images Edits API..."
    $response = $client.PostAsync("https://api.openai.com/v1/images/edits", $form).GetAwaiter().GetResult()
    $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $EndedAt = Get-Date

    if (-not $response.IsSuccessStatusCode) {
        throw "Image edit API request failed: $([int]$response.StatusCode) $($response.ReasonPhrase) $responseText"
    }

    $ResponseJson = $responseText | ConvertFrom-Json
    $ImageB64 = Get-ImageB64 -Response $ResponseJson
    if ([string]::IsNullOrWhiteSpace($ImageB64)) {
        throw "Image edit API returned no image data."
    }

    [System.IO.File]::WriteAllBytes($OutputPath, [Convert]::FromBase64String($ImageB64))
    $DurationSeconds = [math]::Round(($EndedAt - $StartedAt).TotalSeconds, 2)
    $Usage = if ($ResponseJson.usage) { $ResponseJson.usage } else { $null }

    $Report = [ordered]@{
        generated_at = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
        task_id = $TaskId
        book_name = $BookName
        task = "KDP cover repair image edit"
        script = "kdp-fix-image-edit.ps1"
        endpoint = "https://api.openai.com/v1/images/edits"
        image_model = $ImageModel
        duration_seconds = $DurationSeconds
        source_image = $SourcePath
        prompt_file = $PromptPath
        output_image = $OutputPath
        usage = $Usage
        prompt = $Prompt
        response_id = if ($ResponseJson.id) { "$($ResponseJson.id)" } else { "" }
        response_status = if ($ResponseJson.status) { "$($ResponseJson.status)" } else { "" }
    }
    Write-JsonUtf8 -Data $Report -Path $ReportJsonPath -Depth 60

    $NextState = [ordered]@{
        updatedAt = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
        taskId = $TaskId
        model = $ImageModel
        sourceFileName = [System.IO.Path]::GetFileName($SourcePath)
        sourcePath = $SourcePath
        promptFileName = if ($PromptPath) { [System.IO.Path]::GetFileName($PromptPath) } else { "" }
        promptPath = $PromptPath
        prompt = $Prompt
        outputFileName = $OutputName
        outputPath = $OutputPath
        latestRunReportPath = $ReportJsonPath
        latestRun = [ordered]@{
            durationSeconds = $DurationSeconds
            taskId = $TaskId
            usage = $Usage
            responseId = $Report.response_id
            responseStatus = $Report.response_status
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
        "# KDP Fix Image Edit Report",
        "",
        "- Generated at: $($Report.generated_at)",
        "- Task ID: $TaskId",
        "- Task: $($Report.task)",
        "- Program: kdp-fix-image-edit.ps1",
        "- BookName: $BookName",
        "- Endpoint: OpenAI Images Edits API",
        "- Image model: $ImageModel",
        "- Source image: $SourcePath",
        "- Prompt file: $PromptPath",
        "- Output image: $OutputPath",
        "- Duration seconds: $DurationSeconds",
        "",
        "## Usage",
        "",
        $(if ($Usage) { ($Usage | ConvertTo-Json -Depth 40) } else { "No usage object returned by image edit response." }),
        "",
        "## Prompt",
        "",
        $Prompt
    )
    Write-TextUtf8 -Content ($ReportLines -join "`r`n") -Path $ReportMdPath

    Write-Host ""
    Write-Host "KDP fix image edit completed successfully."
    Write-Host "Task ID: $TaskId"
    Write-Host "Called task: KDP cover repair image edit"
    Write-Host "Called program: kdp-fix-image-edit.ps1"
    Write-Host "Image model: $ImageModel"
    Write-Host "Output image: $OutputPath"
    Write-Host "Duration seconds: $DurationSeconds"
    Write-UsageReport -Usage $Usage
}
finally {
    if ($fileStream) { $fileStream.Dispose() }
    if ($form) { $form.Dispose() }
    if ($client) { $client.Dispose() }
}
