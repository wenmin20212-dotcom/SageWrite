Option Explicit

Dim shell
Dim args
Dim scriptPath
Dim title
Dim command

Set shell = CreateObject("WScript.Shell")
Set args = WScript.Arguments

If args.Count < 1 Then
  WScript.Quit 1
End If

scriptPath = args.Item(0)
title = ""
If args.Count >= 2 Then
  title = args.Item(1)
End If

command = "powershell.exe -NoExit -ExecutionPolicy Bypass -File """ & scriptPath & """"
shell.Run command, 1, False
WScript.Sleep 1200
On Error Resume Next
If title <> "" Then
  shell.AppActivate title
Else
  shell.AppActivate "Windows PowerShell"
End If
On Error GoTo 0
