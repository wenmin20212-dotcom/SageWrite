param(
    [string]$WorkspaceRoot,
    [string]$PowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
)

$ErrorActionPreference = 'Stop'
$ServerRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($WorkspaceRoot) {
    $env:SAGEWRITE_WORKSPACE_ROOT = [System.IO.Path]::GetFullPath($WorkspaceRoot)
}
$env:SAGEWRITE_POWERSHELL = $PowerShellPath

$NodePath = if (-not [string]::IsNullOrWhiteSpace($env:SAGEWRITE_NODE_PATH)) {
    $env:SAGEWRITE_NODE_PATH
}
else {
    $NodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $NodeCommand) {
        throw 'Node.js 20 or later was not found. Add node.exe to PATH or set SAGEWRITE_NODE_PATH.'
    }
    $NodeCommand.Source
}

& $NodePath (Join-Path $ServerRoot 'src\index.mjs')
exit $LASTEXITCODE
