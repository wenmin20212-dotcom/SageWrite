[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Assert-FileExists {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description not found: $Path"
    }
}

function Read-JsonUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)
    Assert-FileExists -Path $Path -Description "JSON file"
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "JSON file is empty: $Path"
    }
    return $raw | ConvertFrom-Json
}

function Write-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]$Data,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 40
    )
    Ensure-Directory -Path (Split-Path -Parent $Path)
    $json = $Data | ConvertTo-Json -Depth $Depth
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Write-TextUtf8 {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Path
    )
    Ensure-Directory -Path (Split-Path -Parent $Path)
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Get-StringValue {
    param($Value)
    if ($null -eq $Value) {
        return ""
    }
    return "$Value"
}

function Read-FrontMatterValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $pattern = '^\s*' + [Regex]::Escape($Key) + '\s*:\s*(.+?)\s*$'
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match $pattern) {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Get-TocChapterTitles {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }
    $titles = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^###\s+(.+)$') {
            $titles.Add($Matches[1].Trim())
        }
    }
    return @($titles)
}

function Get-NextCoverRoots {
    param(
        [Parameter(Mandatory = $true)][string]$BookName,
        [ValidateSet("ebook", "print")][string]$Edition = "ebook"
    )
    $enginePath = $PSScriptRoot
    $sageRoot = Split-Path -Parent $enginePath
    $clawRoot = Split-Path -Parent $sageRoot
    $workspaceParentRoot = if (-not [string]::IsNullOrWhiteSpace($env:SAGEWRITE_WORKSPACE_ROOT)) { [System.IO.Path]::GetFullPath($env:SAGEWRITE_WORKSPACE_ROOT) } else { $clawRoot }
    $workspaceRoot = Join-Path $workspaceParentRoot "workspace-$BookName"
    $bookRoot = Join-Path $workspaceRoot "sagewrite\book"
    $nextRoot = Join-Path $bookRoot "07_cover\next\$Edition"
    return [ordered]@{
        engine = $enginePath
        workspace = $workspaceRoot
        book = $bookRoot
        brief = Join-Path $bookRoot "00_brief"
        outline = Join-Path $bookRoot "01_outline"
        old_cover = Join-Path $bookRoot "07_cover\$Edition"
        next = $nextRoot
        base = Join-Path $nextRoot "base"
        prompts = Join-Path $nextRoot "prompts"
        imports = Join-Path $nextRoot "imports"
        reviews = Join-Path $nextRoot "reviews"
        layout = Join-Path $nextRoot "layout"
        print_spread = Join-Path $nextRoot "print_spread"
        mockup = Join-Path $nextRoot "mockup"
        final = Join-Path $nextRoot "final"
        logs = Join-Path $bookRoot "logs"
    }
}

function Initialize-NextCoverRoots {
    param($Roots)
    foreach ($key in @("next", "base", "prompts", "imports", "reviews", "layout", "print_spread", "mockup", "final", "logs")) {
        Ensure-Directory -Path $Roots[$key]
    }
}

function Clear-DirectoryFiles {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Convert-InchesToMillimeters {
    param([Parameter(Mandatory = $true)][double]$Inches)
    return [Math]::Round(($Inches * 25.4), 2)
}

function Convert-InchesToPixels {
    param(
        [Parameter(Mandatory = $true)][double]$Inches,
        [Parameter(Mandatory = $true)][int]$Dpi
    )
    return [int][Math]::Round($Inches * $Dpi)
}

function Get-KdpCoverSpec {
    param(
        [double]$TrimWidthIn = 6.0,
        [double]$TrimHeightIn = 9.0,
        [double]$BleedIn = 0.125,
        [double]$SpineWidthIn = 0.595,
        [int]$PageCount = 264,
        [int]$Dpi = 300
    )
    $coverWidthIn = $BleedIn + $TrimWidthIn + $SpineWidthIn + $TrimWidthIn + $BleedIn
    $coverHeightIn = $BleedIn + $TrimHeightIn + $BleedIn
    return [ordered]@{
        formula = "Cover Width = Bleed + Back Cover Width + Spine Width + Front Cover Width + Bleed; Cover Height = Bleed + Trim Height + Bleed"
        trim_width_in = [Math]::Round($TrimWidthIn, 3)
        trim_height_in = [Math]::Round($TrimHeightIn, 3)
        page_count = $PageCount
        bleed_in = [Math]::Round($BleedIn, 3)
        bleed_mm = Convert-InchesToMillimeters -Inches $BleedIn
        spine_width_in = [Math]::Round($SpineWidthIn, 3)
        spine_width_mm = Convert-InchesToMillimeters -Inches $SpineWidthIn
        cover_width_in = [Math]::Round($coverWidthIn, 3)
        cover_height_in = [Math]::Round($coverHeightIn, 3)
        cover_width_mm = Convert-InchesToMillimeters -Inches $coverWidthIn
        cover_height_mm = Convert-InchesToMillimeters -Inches $coverHeightIn
        dpi = $Dpi
        pixel_width = Convert-InchesToPixels -Inches $coverWidthIn -Dpi $Dpi
        pixel_height = Convert-InchesToPixels -Inches $coverHeightIn -Dpi $Dpi
    }
}

function Get-SafeFont {
    param(
        [Parameter(Mandatory = $true)][string[]]$Candidates,
        [Parameter(Mandatory = $true)][float]$Size,
        [Parameter(Mandatory = $true)][System.Drawing.FontStyle]$Style
    )
    foreach ($name in $Candidates) {
        try {
            return New-Object System.Drawing.Font($name, $Size, $Style, [System.Drawing.GraphicsUnit]::Pixel)
        }
        catch {
        }
    }
    return New-Object System.Drawing.Font("Arial", $Size, $Style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Split-TextLines {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [int]$MaxChars = 12
    )
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $buffer = ""
    foreach ($ch in $Text.Trim().ToCharArray()) {
        $buffer += [string]$ch
        if ($buffer.Length -ge $MaxChars) {
            $lines.Add($buffer.Trim())
            $buffer = ""
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($buffer)) {
        $lines.Add($buffer.Trim())
    }
    return @($lines)
}

function Write-AsciiToStream {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
    $Stream.Write($bytes, 0, $bytes.Length)
}

function Save-BitmapAsSinglePagePdf {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][double]$PageWidthIn,
        [Parameter(Mandatory = $true)][double]$PageHeightIn
    )
    $pageWidthPt = [Math]::Round($PageWidthIn * 72, 3)
    $pageHeightPt = [Math]::Round($PageHeightIn * 72, 3)
    $jpegStream = New-Object System.IO.MemoryStream
    $fileStream = $null
    try {
        $Bitmap.Save($jpegStream, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $jpegBytes = $jpegStream.ToArray()
        $content = "q`n$pageWidthPt 0 0 $pageHeightPt 0 0 cm`n/Im0 Do`nQ`n"
        $contentBytes = [System.Text.Encoding]::ASCII.GetBytes($content)
        $offsets = New-Object System.Collections.Generic.List[long]
        $fileStream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        Write-AsciiToStream -Stream $fileStream -Text "%PDF-1.4`n% SageWrite next cover`n"
        $offsets.Add($fileStream.Position)
        Write-AsciiToStream -Stream $fileStream -Text "1 0 obj`n<< /Type /Catalog /Pages 2 0 R >>`nendobj`n"
        $offsets.Add($fileStream.Position)
        Write-AsciiToStream -Stream $fileStream -Text "2 0 obj`n<< /Type /Pages /Kids [3 0 R] /Count 1 >>`nendobj`n"
        $offsets.Add($fileStream.Position)
        Write-AsciiToStream -Stream $fileStream -Text "3 0 obj`n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageWidthPt $pageHeightPt] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>`nendobj`n"
        $offsets.Add($fileStream.Position)
        Write-AsciiToStream -Stream $fileStream -Text "4 0 obj`n<< /Type /XObject /Subtype /Image /Width $($Bitmap.Width) /Height $($Bitmap.Height) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length $($jpegBytes.Length) >>`nstream`n"
        $fileStream.Write($jpegBytes, 0, $jpegBytes.Length)
        Write-AsciiToStream -Stream $fileStream -Text "`nendstream`nendobj`n"
        $offsets.Add($fileStream.Position)
        Write-AsciiToStream -Stream $fileStream -Text "5 0 obj`n<< /Length $($contentBytes.Length) >>`nstream`n"
        $fileStream.Write($contentBytes, 0, $contentBytes.Length)
        Write-AsciiToStream -Stream $fileStream -Text "endstream`nendobj`n"
        $xrefStart = $fileStream.Position
        Write-AsciiToStream -Stream $fileStream -Text "xref`n0 6`n0000000000 65535 f `n"
        foreach ($offset in $offsets) {
            Write-AsciiToStream -Stream $fileStream -Text ("{0:D10} 00000 n `n" -f $offset)
        }
        Write-AsciiToStream -Stream $fileStream -Text "trailer`n<< /Size 6 /Root 1 0 R >>`nstartxref`n$xrefStart`n%%EOF`n"
    }
    finally {
        if ($null -ne $fileStream) { $fileStream.Dispose() }
        $jpegStream.Dispose()
    }
}
