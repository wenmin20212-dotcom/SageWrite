param(
    [int]$Port = 3210,
    [switch]$OpenBrowser
)

$ErrorActionPreference = "Stop"

$EnginePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebRoot = Join-Path $EnginePath "webui"

if (!(Test-Path $WebRoot)) {
    Write-Error "webui folder not found: $WebRoot"
    exit 1
}

if (!(Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js not found."
    exit 1
}

Push-Location $WebRoot

try {
    $env:PORT = "$Port"

    if ($OpenBrowser) {
        $url = "http://127.0.0.1:$Port"
        Start-Job -ScriptBlock {
            param($TargetUrl)
            Start-Sleep -Seconds 2
            Start-Process $TargetUrl
        } -ArgumentList $url | Out-Null
    }

    & node "server.js"
}
finally {
    Pop-Location
}
