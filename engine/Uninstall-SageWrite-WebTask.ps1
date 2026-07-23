param(
  [string]$TaskName = "SageWrite Web",
  [switch]$Stop
)

$ErrorActionPreference = "Stop"

$Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (!$Task) {
  Write-Host "Scheduled task not found: $TaskName"
  exit 0
}

if ($Stop) {
  Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Host "Uninstalled scheduled task: $TaskName"
