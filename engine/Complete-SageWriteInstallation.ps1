param(
    [ValidateSet('Writing', 'Web')]
    [string]$Profile = 'Writing',
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'
$ReportDirectory = Join-Path $PSScriptRoot 'work/environment-reports'
$CheckArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
    (Join-Path $PSScriptRoot 'Test-SageWriteEnvironment.ps1'),
    '-Profile', $Profile, '-Json', '-ReportDirectory', $ReportDirectory)
if (-not [string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $CheckArguments += @('-WorkspaceRoot', $WorkspaceRoot)
}
$CheckOutput = & powershell.exe @CheckArguments
$CheckExitCode = $LASTEXITCODE
if ($CheckExitCode -notin @(0, 1)) {
    throw 'Post-install environment inspection could not complete.'
}
$Report = ($CheckOutput -join "`n") | ConvertFrom-Json
if ($Report.schema_version -ne 1 -or $null -eq $Report.counts.fail) {
    throw 'Post-install environment inspection returned an invalid report.'
}
Write-Output ($Report | ConvertTo-Json -Depth 8)
Write-Host "Environment reports: $ReportDirectory"
Write-Host 'Agent: read skills/sagewrite-manage-environment/SKILL.md, section Installation handoff.'
Write-Host 'Present the installation result and welcome message in the user conversation, in the user language.'
Write-Host 'Include project/workspace paths, selected capabilities, blockers, warnings, untested features, report link and next step.'
if ($Report.counts.fail -gt 0) {
    Write-Warning 'Installation setup finished, but selected environment checks have blockers. Report partial completion and next actions.'
} else {
    Write-Host 'Installation setup finished and selected static checks passed. Welcome the user with the checked scope; runtime behavior still needs validation.'
}
exit $CheckExitCode
