param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("List", "OpenDirectory")]
    [string]$Action = "List"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\08n-common.ps1"

function Get-KdpAcceptanceRoots {
    param([Parameter(Mandatory = $true)][string]$BookName)

    $enginePath = $PSScriptRoot
    $sageRoot = Split-Path -Parent $enginePath
    $clawRoot = Split-Path -Parent $sageRoot
    $workspaceParentRoot = if (-not [string]::IsNullOrWhiteSpace($env:SAGEWRITE_WORKSPACE_ROOT)) { [System.IO.Path]::GetFullPath($env:SAGEWRITE_WORKSPACE_ROOT) } else { $clawRoot }
    $workspaceRoot = Join-Path $workspaceParentRoot "workspace-$BookName"
    $bookRoot = Join-Path $workspaceRoot "sagewrite\book"
    $acceptanceRoot = Join-Path $bookRoot "07_cover\kdp_acceptance"
    return [ordered]@{
        engine = $enginePath
        workspace = $workspaceRoot
        book = $bookRoot
        acceptance = $acceptanceRoot
    }
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "File is outside KDP acceptance directory: $Path"
    }
    return $pathFull.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-KdpAcceptanceFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return @()
    }

    $extensions = @(".pdf", ".png")
    $files = Get-ChildItem -LiteralPath $Root -File -Recurse |
        Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object -Property LastWriteTime, Name -Descending

    $result = @()
    foreach ($file in $files) {
        $relative = Get-RelativePath -Root $Root -Path $file.FullName
        $folder = Split-Path -Parent $relative
        $role = "acceptance"
        if ($relative -like "fix_workbench/source/*") { $role = "fix-source" }
        elseif ($relative -like "fix_workbench/output/*") { $role = "fix-output" }
        elseif ($relative -like "llm_text_regions/*") { $role = "llm-cache" }

        $type = if ($file.Extension.ToLowerInvariant() -eq ".pdf") { "pdf" } else { "png" }
        $result += [ordered]@{
            name = $file.Name
            relativePath = $relative
            folder = $folder
            type = $type
            role = $role
            sizeBytes = $file.Length
            modifiedAt = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            fullPath = $file.FullName
        }
    }
    return $result
}

$Roots = Get-KdpAcceptanceRoots -BookName $BookName
Ensure-Directory -Path $Roots.acceptance

if ($Action -eq "OpenDirectory") {
    Write-Host "KDP acceptance files task started."
    Write-Host "Task: open KDP acceptance directory"
    Write-Host "Program: kdp-acceptance-files.ps1"
    Write-Host "BookName: $BookName"
    Write-Host "Directory: $($Roots.acceptance)"
    if ($env:SAGEWRITE_MODE -eq "cloud") {
        Write-Host "Cloud mode: Explorer is not opened. Use the web file list/download controls."
        return
    }
    Start-Process -FilePath "explorer.exe" -ArgumentList @($Roots.acceptance) | Out-Null
    Write-Host "KDP acceptance directory opened."
    return
}

$payload = [ordered]@{
    bookName = $BookName
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    task = "list KDP acceptance files"
    program = "kdp-acceptance-files.ps1"
    acceptanceRoot = $Roots.acceptance
    files = @(Get-KdpAcceptanceFiles -Root $Roots.acceptance)
}

$payload | ConvertTo-Json -Depth 20
