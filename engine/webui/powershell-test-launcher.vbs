Option Explicit

Dim shell
Dim fso
Dim baseDir
Dim scriptPath
Dim command

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = baseDir & "\powershell-test-window.ps1"
command = "powershell.exe -NoExit -ExecutionPolicy Bypass -File """ & scriptPath & """"

shell.Run command, 1, False
WScript.Sleep 1200
On Error Resume Next
shell.AppActivate "SageWrite Test Button"
On Error GoTo 0
