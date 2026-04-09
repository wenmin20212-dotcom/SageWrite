function ConvertTo-SageHashtable {
    param(
        [Parameter(Mandatory=$true)]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $Result = @{}
        foreach ($key in $InputObject.Keys) {
            $Result[$key] = ConvertTo-SageHashtable -InputObject $InputObject[$key]
        }
        return $Result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $Items = @()
        foreach ($item in $InputObject) {
            $Items += ConvertTo-SageHashtable -InputObject $item
        }
        return $Items
    }

    if ($InputObject -is [pscustomobject] -or $InputObject.GetType().Name -eq "PSCustomObject") {
        $Result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $Result[$property.Name] = ConvertTo-SageHashtable -InputObject $property.Value
        }
        return $Result
    }

    return $InputObject
}

function Get-SageContext {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath,

        [Parameter(Mandatory=$true)]
        [string]$BookName
    )

    $EnginePath = Split-Path -Parent $ScriptPath
    $SageRoot   = Split-Path -Parent $EnginePath
    $ClawRoot   = Split-Path -Parent $SageRoot

    $WorkspaceRoot = Join-Path $ClawRoot "workspace-$BookName"
    $BookRoot      = Join-Path $WorkspaceRoot "sagewrite\book"
    $LogRoot       = Join-Path $BookRoot "logs"
    $RunLogPath    = Join-Path $LogRoot "run_history.jsonl"
    $StatusPath    = Join-Path $LogRoot "status.json"

    return @{
        EnginePath    = $EnginePath
        SageRoot      = $SageRoot
        ClawRoot      = $ClawRoot
        WorkspaceRoot = $WorkspaceRoot
        BookRoot      = $BookRoot
        LogRoot       = $LogRoot
        RunLogPath    = $RunLogPath
        StatusPath    = $StatusPath
    }
}

function Initialize-SageObservability {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Context
    )

    try {
        if (!(Test-Path $Context.LogRoot)) {
            New-Item -ItemType Directory -Path $Context.LogRoot -Force | Out-Null
        }

        if (!(Test-Path $Context.RunLogPath)) {
            [System.IO.File]::WriteAllText(
                $Context.RunLogPath,
                "",
                [System.Text.UTF8Encoding]::new($true)
            )
        }

        if (!(Test-Path $Context.StatusPath)) {
            $InitialStatus = @{
                book = Split-Path $Context.WorkspaceRoot -Leaf
                workspace_path = $Context.WorkspaceRoot
                updated_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                current = $null
                last_run = $null
                last_success = $null
                last_error = $null
                steps = @{}
                artifacts = @{}
            }
            $InitialStatus | ConvertTo-Json -Depth 10 | Out-File $Context.StatusPath -Encoding utf8
        }
    }
    catch {
        return
    }
}

function Read-SageStatus {
    param(
        [Parameter(Mandatory=$true)]
        [string]$StatusPath
    )

    if (!(Test-Path $StatusPath)) {
        return @{
            updated_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            current = $null
            last_run = $null
            last_success = $null
            last_error = $null
            steps = @{}
            artifacts = @{}
        }
    }

    try {
        $Parsed = Get-Content $StatusPath -Raw | ConvertFrom-Json
        return ConvertTo-SageHashtable -InputObject $Parsed
    }
    catch {
        return @{
            updated_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            current = $null
            last_run = $null
            last_success = $null
            last_error = @{
                message = "status.json unreadable"
                time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            steps = @{}
            artifacts = @{}
        }
    }
}

function Save-SageStatus {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Status,

        [Parameter(Mandatory=$true)]
        [string]$StatusPath
    )

    try {
        $Status.updated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Status | ConvertTo-Json -Depth 12 | Out-File $StatusPath -Encoding utf8
    }
    catch {
        return
    }
}

function Add-SageArtifactSnapshot {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Context
    )

    try {
        $Status = Read-SageStatus -StatusPath $Context.StatusPath
    }
    catch {
        return
    }

    $ObjectivePath = Join-Path $Context.BookRoot "00_brief\objective.md"
    $TocPath       = Join-Path $Context.BookRoot "01_outline\toc.md"
    $Toc2Path      = Join-Path $Context.BookRoot "01_outline\toc2.md"
    $ChapterRoot   = Join-Path $Context.BookRoot "02_chapters"
    $OutputRoot    = Join-Path $Context.BookRoot "04_output"

    $ChapterFiles = @()
    if (Test-Path $ChapterRoot) {
        $ChapterFiles = Get-ChildItem $ChapterRoot -Filter *.md |
            Where-Object { $_.Name -notmatch "^_" } |
            Sort-Object Name |
            Select-Object -ExpandProperty Name
    }

    $OutputFiles = @()
    if (Test-Path $OutputRoot) {
        $OutputFiles = Get-ChildItem $OutputRoot -Recurse -File |
            Where-Object {
                $_.FullName -notmatch '\\back\\' -and
                $_.Name -notmatch '^~\$' -and
                @('.docx', '.epub', '.pdf') -contains $_.Extension.ToLowerInvariant()
            } |
            Sort-Object FullName |
            ForEach-Object {
                $_.FullName.Substring($OutputRoot.Length).TrimStart('\')
            }
    }

    $Status.artifacts = @{
        objective_exists = (Test-Path $ObjectivePath)
        toc_exists = (Test-Path $TocPath)
        toc2_exists = (Test-Path $Toc2Path)
        chapter_count = $ChapterFiles.Count
        chapter_files = $ChapterFiles
        output_count = $OutputFiles.Count
        output_files = $OutputFiles
    }

    Save-SageStatus -Status $Status -StatusPath $Context.StatusPath
}

function Set-SageCurrentStep {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Context,

        [Parameter(Mandatory=$true)]
        [string]$Step,

        [hashtable]$Data = @{}
    )

    try {
        $Status = Read-SageStatus -StatusPath $Context.StatusPath
        $Status.current = @{
            step = $Step
            state = "running"
            started_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            data = $Data
        }
        Save-SageStatus -Status $Status -StatusPath $Context.StatusPath
    }
    catch {
        return
    }
}

function Write-SageRunLog {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Context,

        [Parameter(Mandatory=$true)]
        [hashtable]$Entry
    )

    try {
        Initialize-SageObservability -Context $Context

        $Entry.timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Json = $Entry | ConvertTo-Json -Depth 12 -Compress
        Add-Content -Path $Context.RunLogPath -Value $Json -Encoding utf8
    }
    catch {
        return
    }
}

function Complete-SageStep {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Context,

        [Parameter(Mandatory=$true)]
        [string]$Step,

        [Parameter(Mandatory=$true)]
        [string]$State,

        [string]$Message = "",

        [hashtable]$Data = @{}
    )

    try {
        Add-SageArtifactSnapshot -Context $Context
    }
    catch {
        return
    }

    $Now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        $Status = Read-SageStatus -StatusPath $Context.StatusPath
    }
    catch {
        return
    }

    if (-not $Status.steps) {
        $Status.steps = @{}
    }

    $StepData = @{
        state = $State
        message = $Message
        finished_at = $Now
        data = $Data
    }

    $Status.steps[$Step] = $StepData
    $Status.last_run = @{
        step = $Step
        state = $State
        time = $Now
        message = $Message
        data = $Data
    }

    if ($State -eq "success") {
        $Status.last_success = @{
            step = $Step
            time = $Now
            message = $Message
        }
        $Status.last_error = $null
    }

    if ($State -eq "failed") {
        $Status.last_error = @{
            step = $Step
            time = $Now
            message = $Message
            data = $Data
        }
    }

    $Status.current = @{
        step = $Step
        state = $State
        finished_at = $Now
        data = $Data
    }

    Save-SageStatus -Status $Status -StatusPath $Context.StatusPath

    Write-SageRunLog -Context $Context -Entry @{
        step = $Step
        state = $State
        message = $Message
        data = $Data
    }
}

function Fail-SageStep {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Context,

        [Parameter(Mandatory=$true)]
        [string]$Step,

        [Parameter(Mandatory=$true)]
        [string]$Message,

        [hashtable]$Data = @{}
    )

    Complete-SageStep -Context $Context -Step $Step -State "failed" -Message $Message -Data $Data
}
