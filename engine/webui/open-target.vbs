Option Explicit

Dim shellApp
Dim args
Dim targetPath

Set shellApp = CreateObject("Shell.Application")
Set args = WScript.Arguments

If args.Count < 1 Then
  WScript.Quit 1
End If

targetPath = args.Item(0)
shellApp.ShellExecute targetPath, "", "", "open", 1
