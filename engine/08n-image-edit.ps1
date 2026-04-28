param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$InputFile,

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,
    [string]$Publisher,
    [string]$CoverText,

    [string]$ImageModel = "gpt-image-1.5",

    [switch]$Force
)

. "$PSScriptRoot\08n-common.ps1"

function Get-LatestBaseImage {
    param([Parameter(Mandatory = $true)][string]$ImportRoot)

    $files = Get-ChildItem -LiteralPath $ImportRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|webp)$' } |
        Sort-Object LastWriteTime -Descending

    if (-not $files -or $files.Count -lt 1) {
        return $null
    }
    return $files[0].FullName
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
    param([Parameter(Mandatory = $true)]$Response)

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

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots

$ObjectivePath = Join-Path $Roots.brief "objective.md"
if ([string]::IsNullOrWhiteSpace($Title)) { $Title = Read-FrontMatterValue -Path $ObjectivePath -Key "title" }
if ([string]::IsNullOrWhiteSpace($Subtitle)) { $Subtitle = Read-FrontMatterValue -Path $ObjectivePath -Key "subtitle" }
if ([string]::IsNullOrWhiteSpace($Author)) { $Author = Read-FrontMatterValue -Path $ObjectivePath -Key "author" }
if ([string]::IsNullOrWhiteSpace($Publisher)) {
    $Publisher = Read-FrontMatterValue -Path $ObjectivePath -Key "publisher"
}
if ([string]::IsNullOrWhiteSpace($Publisher)) {
    $Publisher = Read-FrontMatterValue -Path $ObjectivePath -Key "imprint"
}

$ResolvedTitle = Get-StringValue $Title
$ResolvedSubtitle = Get-StringValue $Subtitle
$ResolvedAuthor = Get-StringValue $Author
$ResolvedPublisher = Get-StringValue $Publisher

if ([string]::IsNullOrWhiteSpace($CoverText)) {
    $CoverText = @(
        "Title: $ResolvedTitle",
        "Subtitle: $ResolvedSubtitle",
        "Author: $ResolvedAuthor",
        "Publisher: $ResolvedPublisher"
    ) -join "`n"
}

if ([string]::IsNullOrWhiteSpace($ResolvedTitle)) {
    throw "Title is required for image editing."
}

if ($InputFile) {
    $candidate = Join-Path $Roots.imports ([System.IO.Path]::GetFileName($InputFile))
    Assert-FileExists -Path $candidate -Description "input base image"
    $InputPath = $candidate
} else {
    $InputPath = Get-LatestBaseImage -ImportRoot $Roots.imports
    if (-not $InputPath) {
        throw "No imported base image found. Save a base image into 07_cover\next\$Edition\imports first."
    }
}

if (-not $env:OPENAI_API_KEY) {
    throw "OPENAI_API_KEY not set."
}

Ensure-Directory -Path $Roots.layout
$Stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$OutputName = "ai_edited_cover_$Stamp.png"
$OutputPath = Join-Path $Roots.layout $OutputName
$ReportJsonPath = Join-Path $Roots.layout "ai_image_edit_report.json"
$ReportMdPath = Join-Path $Roots.layout "ai_image_edit_report.md"
$WorkbenchStatePath = Join-Path $Roots.next "workbench_state.json"

if ((Test-Path -LiteralPath $OutputPath) -and (-not $Force)) {
    throw "Output already exists: $OutputPath"
}

$Prompt = @"
Edit the provided book cover image into a finished professional front cover.

Critical image editing instructions:
- Remove or paint over every existing character, word, number, logo, watermark, caption, label, signage, and any mark that resembles text in the source image.
- Preserve the strongest visual qualities of the base artwork: composition, atmosphere, color mood, texture, depth, and cinematic rendering.
- Add ONLY the following four book-cover text elements, with accurate spelling and no extra words:
$CoverText
- Create a clean premium nonfiction book cover typography layout.
- Make the title the dominant element, the subtitle secondary, the author smaller, and the publisher/imprint small but legible.
- Keep all text inside safe margins. Do not crop or distort the text.
- Do not add barcode, price, stickers, slogans, blurbs, awards, or any extra decorative text.
- Output a single finished front cover image.
"@

Add-Type -AssemblyName System.Net.Http
$client = [System.Net.Http.HttpClient]::new()
$fileStream = $null
$form = $null
try {
    $client.Timeout = [TimeSpan]::FromMinutes(5)
    $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $env:OPENAI_API_KEY)
    $form = [System.Net.Http.MultipartFormDataContent]::new()
    $form.Add([System.Net.Http.StringContent]::new($ImageModel, [System.Text.Encoding]::UTF8), "model")
    $form.Add([System.Net.Http.StringContent]::new($Prompt, [System.Text.Encoding]::UTF8), "prompt")
    $form.Add([System.Net.Http.StringContent]::new("1024x1536", [System.Text.Encoding]::UTF8), "size")
    $form.Add([System.Net.Http.StringContent]::new("png", [System.Text.Encoding]::UTF8), "output_format")
    $form.Add([System.Net.Http.StringContent]::new("high", [System.Text.Encoding]::UTF8), "quality")

    $fileStream = [System.IO.File]::OpenRead($InputPath)
    $imageContent = [System.Net.Http.StreamContent]::new($fileStream)
    $imageContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse((Get-ImageMimeType -Path $InputPath))
    $form.Add($imageContent, "image", [System.IO.Path]::GetFileName($InputPath))

    $StartedAt = Get-Date
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
        book_name = $BookName
        edition = $Edition
        script = "08n-image-edit.ps1"
        endpoint = "https://api.openai.com/v1/images/edits"
        image_model = $ImageModel
        duration_seconds = $DurationSeconds
        source_image = $InputPath
        output_image = $OutputPath
        cover_text = [ordered]@{
            title = $ResolvedTitle
            subtitle = $ResolvedSubtitle
            author = $ResolvedAuthor
            publisher = $ResolvedPublisher
            raw = $CoverText
        }
        usage = $Usage
        prompt = $Prompt
    }

    Write-JsonUtf8 -Data $Report -Path $ReportJsonPath
    $WorkbenchState = if (Test-Path -LiteralPath $WorkbenchStatePath) {
        try { Read-JsonUtf8 -Path $WorkbenchStatePath } catch { $null }
    } else {
        $null
    }
    $NextWorkbenchState = [ordered]@{
        updated_at = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
        latest_import_file = [System.IO.Path]::GetFileName($InputPath)
        selected_import_file = [System.IO.Path]::GetFileName($InputPath)
        latest_import_path = $InputPath
        latest_edited_file = $OutputName
        latest_edited_path = $OutputPath
        edit_text = $CoverText
        publisher = $ResolvedPublisher
        image_model = $ImageModel
    }
    if ($WorkbenchState) {
        foreach ($property in $WorkbenchState.PSObject.Properties) {
            if (-not $NextWorkbenchState.Contains($property.Name)) {
                $NextWorkbenchState[$property.Name] = $property.Value
            }
        }
    }
    Write-JsonUtf8 -Data $NextWorkbenchState -Path $WorkbenchStatePath
    $ReportLines = @(
        "# AI Image Edit Report",
        "",
        "- Generated at: $($Report.generated_at)",
        "- BookName: $BookName",
        "- Edition: $Edition",
        "- Script: 08n-image-edit.ps1",
        "- Endpoint: OpenAI Image Edits API",
        "- Image model: $ImageModel",
        "- Source image: $InputPath",
        "- Output image: $OutputPath",
        "- Duration seconds: $DurationSeconds",
        "",
        "## Cover Text",
        "",
        $CoverText,
        "",
        "## Usage",
        "",
        $(if ($Usage) { ($Usage | ConvertTo-Json -Depth 20) } else { "No usage object returned by image edit response." }),
        "",
        "## Prompt",
        "",
        $Prompt
    )
    Write-TextUtf8 -Content ($ReportLines -join "`r`n") -Path $ReportMdPath

    Write-Host "08n-image-edit completed successfully."
    Write-Host "Script: 08n-image-edit.ps1"
    Write-Host "Image model: $ImageModel"
    Write-Host "Endpoint: OpenAI Image Edits API"
    Write-Host "Source image: $InputPath"
    Write-Host "Output image: $OutputPath"
    if ($Usage) {
        Write-Host ("Usage: " + ($Usage | ConvertTo-Json -Depth 20 -Compress))
    } else {
        Write-Host "Usage: not returned by image edit response."
    }
}
finally {
    if ($fileStream) { $fileStream.Dispose() }
    if ($form) { $form.Dispose() }
    if ($client) { $client.Dispose() }
}
