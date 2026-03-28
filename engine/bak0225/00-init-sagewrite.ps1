# ========= SageWrite 引擎初始化 =========

$RootPath = Join-Path (Get-Location) "SageWrite"
$EnginePath = Join-Path $RootPath "engine"

# 创建 SageWrite 根目录
if (!(Test-Path $RootPath)) {
    New-Item -ItemType Directory -Path $RootPath | Out-Null
    Write-Host "Created: $RootPath"
}

# 创建 engine 目录
if (!(Test-Path $EnginePath)) {
    New-Item -ItemType Directory -Path $EnginePath | Out-Null
    Write-Host "Created: $EnginePath"
}

# 需要创建的核心脚本
$Scripts = @(
    "01-intake.ps1",
    "02-structure.ps1",
    "03-write.ps1",
    "04-edit.ps1",
    "05-build.ps1"
)

foreach ($script in $Scripts) {
    $scriptPath = Join-Path $EnginePath $script
    if (!(Test-Path $scriptPath)) {
        New-Item -ItemType File -Path $scriptPath | Out-Null
        Write-Host "Created: $scriptPath"
    }
}
Write-Host "`nSageWrite engine initialized successfully."
# Write-Host "`nSageWrite 引擎结构初始化完成。"