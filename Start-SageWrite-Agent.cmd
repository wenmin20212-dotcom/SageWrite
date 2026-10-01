@echo off
setlocal
title SageWrite Agent
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0engine\Start-SageWrite-Agent.ps1" %*
if errorlevel 1 (
  echo.
  echo SageWrite Agent failed to start. Review the message above.
  pause
)
endlocal
