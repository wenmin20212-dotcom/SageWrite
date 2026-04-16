param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [ValidateSet("all", "amazon", "apple", "google")]
    [string]$Platform = "all",

    [ValidateSet("prepare", "draft", "assist", "details", "content")]
    [string]$Mode = "prepare",

    [switch]$AttachChrome,
    [int]$ChromeDebugPort = 9222,

    [switch]$ReuseSession,
    [switch]$Force
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        $Data
    )
    $Data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-RunLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $script:RunLogPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Invoke-SubmitModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPlatform
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Submit module not found: $ScriptPath"
    }

    $invokeSplat = @{
        BookName = $BookName
        Language = $LanguageCode
        Mode = $Mode
        RunRoot = $RunRoot
    }
    if ($ReuseSession) {
        $invokeSplat.ReuseSession = $true
    }
    if ($TargetPlatform -eq "google" -and $AttachChrome) {
        $invokeSplat.AttachChrome = $true
        $invokeSplat.ChromeDebugPort = $ChromeDebugPort
    }
    if ($Force) {
        $invokeSplat.Force = $true
    }

    Write-RunLog "Running $TargetPlatform submit module."
    & $ScriptPath @invokeSplat | ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "$TargetPlatform submit module failed with exit code $LASTEXITCODE"
    }

    $platformResultPath = Join-Path $RunRoot ($TargetPlatform + "_result.json")
    if (-not (Test-Path -LiteralPath $platformResultPath)) {
        throw "$TargetPlatform submit module did not write result file: $platformResultPath"
    }

    return Read-JsonUtf8 -Path $platformResultPath
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context

$LanguageCode = $Language.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    $LanguageCode = "zh"
}

$SubmitScope = if ($Platform -eq "all") { @("amazon", "apple", "google") } else { @($Platform) }

Set-SageCurrentStep -Context $Context -Step "submit" -Data @{
    language = $LanguageCode
    platform = $Platform
    mode = $Mode
    attach_chrome = [bool]$AttachChrome
    chrome_debug_port = $ChromeDebugPort
}

$BookRoot = $Context.BookRoot
$PublishRoot = Join-Path $BookRoot ("09_publish\" + $LanguageCode)
$PublishMetadataPath = Join-Path $PublishRoot "publish_metadata.json"
$PublishManifestPath = Join-Path $PublishRoot "publish_manifest.json"
$SubmitRunsRoot = Join-Path $PublishRoot "submit_runs"
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$RunRoot = Join-Path $SubmitRunsRoot $RunStamp
$ScreenshotsRoot = Join-Path $RunRoot "screenshots"
$ArtifactsRoot = Join-Path $RunRoot "artifacts"
$script:RunLogPath = Join-Path $RunRoot "session.log"
$RequestPath = Join-Path $RunRoot "submit_request.json"
$ResultPath = Join-Path $RunRoot "submit_result.json"

$AmazonScriptPath = Join-Path $Context.EnginePath "09g-amazon-bot.ps1"
$GoogleScriptPath = Join-Path $Context.EnginePath "09h-google-bot.ps1"
$AppleScriptPath = Join-Path $Context.EnginePath "09i-apple-delivery.ps1"

$ScriptMap = @{
    amazon = $AmazonScriptPath
    google = $GoogleScriptPath
    apple = $AppleScriptPath
}

if (-not (Test-Path -LiteralPath $BookRoot)) {
    Fail-SageStep -Context $Context -Step "submit" -Message "Book root not found." -Data @{
        book_root = $BookRoot
        language = $LanguageCode
        platform = $Platform
        mode = $Mode
    }
    Write-Error "Book root not found: $BookRoot"
    exit 1
}

Ensure-Directory -Path $SubmitRunsRoot
Ensure-Directory -Path $RunRoot
Ensure-Directory -Path $ScreenshotsRoot
Ensure-Directory -Path $ArtifactsRoot
Set-Content -LiteralPath $script:RunLogPath -Value "" -Encoding UTF8

$request = [ordered]@{
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    book_name = $BookName
    language = $LanguageCode
    platform_scope = $Platform
    mode = $Mode
    attach_chrome = [bool]$AttachChrome
    chrome_debug_port = $ChromeDebugPort
    reuse_session = [bool]$ReuseSession
    force = [bool]$Force
    run_root = $RunRoot
    screenshots_root = $ScreenshotsRoot
    artifacts_root = $ArtifactsRoot
}
Write-JsonUtf8 -Path $RequestPath -Data $request

try {
    Write-RunLog "09f-submit started."
    Write-RunLog "Run root: $RunRoot"

    if (-not (Test-Path -LiteralPath $PublishRoot)) {
        throw "09_publish language root not found: $PublishRoot"
    }
    if (-not (Test-Path -LiteralPath $PublishMetadataPath)) {
        throw "publish_metadata.json not found. Run 09-publish.ps1 first."
    }
    if (-not (Test-Path -LiteralPath $PublishManifestPath)) {
        throw "publish_manifest.json not found. Run 09-publish.ps1 first."
    }

    $publishMetadata = Read-JsonUtf8 -Path $PublishMetadataPath
    $publishManifest = Read-JsonUtf8 -Path $PublishManifestPath

    $result = [ordered]@{
        generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        book_name = $BookName
        language = $LanguageCode
        mode = $Mode
        platform_scope = $Platform
        run_root = $RunRoot
        screenshots_root = $ScreenshotsRoot
        artifacts_root = $ArtifactsRoot
        ready = $true
        state = "running"
        summary = ""
        request = $request
        package_snapshot = [ordered]@{
            publish_root = $PublishRoot
            metadata_file = $PublishMetadataPath
            manifest_file = $PublishManifestPath
            title = "$($publishMetadata.title)"
            author = "$($publishMetadata.author)"
            publisher = "$($publishMetadata.publisher)"
        }
        platforms = @()
    }

    foreach ($platformName in $SubmitScope) {
        $platformRoot = Join-Path $PublishRoot $platformName
        $platformMetadataPath = Join-Path $platformRoot "metadata.json"

        if (-not (Test-Path -LiteralPath $platformRoot)) {
            throw "Platform package root not found: $platformRoot"
        }
        if (-not (Test-Path -LiteralPath $platformMetadataPath)) {
            throw "Platform metadata not found: $platformMetadataPath"
        }

        $moduleResult = Invoke-SubmitModule -ScriptPath $ScriptMap[$platformName] -TargetPlatform $platformName
        $result.platforms += $moduleResult
    }

    $result.state = "success"
    $result.summary = "Submit run finished. Review each platform result for readiness and any remaining manual portal steps."
    Write-JsonUtf8 -Path $ResultPath -Data $result

    Complete-SageStep -Context $Context -Step "submit" -State "success" -Message "Submit skeleton finished." -Data @{
        language = $LanguageCode
        platform = $Platform
        mode = $Mode
        run_root = $RunRoot
        platform_count = $result.platforms.Count
    }

    Write-RunLog "09f-submit completed successfully."
    Write-Host ""
    Write-Host "Submit run folder:"
    Write-Host $RunRoot
}
catch {
    $errorMessage = $_.Exception.Message
    Write-RunLog ("ERROR: " + $errorMessage)

    $failure = [ordered]@{
        generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        book_name = $BookName
        language = $LanguageCode
        mode = $Mode
        platform_scope = $Platform
        state = "failed"
        summary = $errorMessage
        run_root = $RunRoot
    }
    Write-JsonUtf8 -Path $ResultPath -Data $failure

    Fail-SageStep -Context $Context -Step "submit" -Message $errorMessage -Data @{
        language = $LanguageCode
        platform = $Platform
        mode = $Mode
        run_root = $RunRoot
    }
    throw
}
