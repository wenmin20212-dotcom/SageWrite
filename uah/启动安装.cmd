@echo off
"%~dp0runtime\node.exe" "%~dp0prepare.cjs" %*
if errorlevel 1 pause
