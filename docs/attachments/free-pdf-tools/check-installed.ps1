param(
    [string]$LibreOfficePath,
    [string]$OnlyOfficePath,
    [string]$OpenOfficePath,
    [string]$ChromiumPath,
    [string]$TypstPath
)

# Read file metadata only. Never start or install these programs.
$ErrorActionPreference = 'Stop'
$Inventory = @(
    @{ Name='LibreOffice'; Path=$LibreOfficePath; Relative='LibreOffice\program\soffice.exe' },
    @{ Name='ONLYOFFICE Desktop'; Path=$OnlyOfficePath; Relative='ONLYOFFICE\DesktopEditors\DesktopEditors.exe' },
    @{ Name='Apache OpenOffice'; Path=$OpenOfficePath; Relative='OpenOffice 4\program\soffice.exe' },
    @{ Name='Chromium'; Path=$ChromiumPath; Relative='Chromium\Application\chrome.exe' },
    @{ Name='Typst'; Path=$TypstPath; Relative='Typst\typst.exe' }
)
foreach ($Tool in $Inventory) {
    $Candidates = @()
    if ($Tool.Path) {
        $Candidates += $Tool.Path
    } else {
        foreach ($Base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
            if ($Base) { $Candidates += (Join-Path $Base $Tool.Relative) }
        }
    }
    $Found = $Candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($Found) {
        $File = Get-Item -LiteralPath $Found
        [pscustomobject]@{ Tool=$Tool.Name; State='file_found_export_unverified'; Path=$File.FullName; FileVersion=$File.VersionInfo.FileVersion }
    } else {
        [pscustomobject]@{ Tool=$Tool.Name; State='not_found_in_checked_paths'; Path=''; FileVersion='' }
    }
}
