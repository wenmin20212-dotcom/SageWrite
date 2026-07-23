param(
  [string]$TaskName = "SageWrite Web"
)

$ErrorActionPreference = "Stop"

$EngineRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogRoot = Join-Path $EngineRoot "logs\web-service"
$LatestPath = Join-Path $LogRoot "latest.log.path.txt"

$Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (!$Task) {
  Write-Host "Scheduled task not found: $TaskName"
} else {
  $Info = Get-ScheduledTaskInfo -TaskName $TaskName
  [pscustomobject]@{
    TaskName = $Task.TaskName
    State = $Task.State
    LastRunTime = $Info.LastRunTime
    LastTaskResult = $Info.LastTaskResult
    NextRunTime = $Info.NextRunTime
    Actions = ($Task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join "; "
    Triggers = ($Task.Triggers | ForEach-Object { $_.CimClass.CimClassName }) -join "; "
  } | Format-List
}

if (Test-Path -LiteralPath $LatestPath) {
  $LogPath = Get-Content -LiteralPath $LatestPath -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($LogPath) {
    Write-Host "LatestLog: $LogPath"
  }
} elseif (Test-Path -LiteralPath $LogRoot) {
  $LatestLog = Get-ChildItem -LiteralPath $LogRoot -Filter "*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($LatestLog) {
    Write-Host "LatestLog: $($LatestLog.FullName)"
  }
}
