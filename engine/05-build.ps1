param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
$LanguageCode = $Language.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    $LanguageCode = "zh"
}
Set-SageCurrentStep -Context $Context -Step "build" -Data @{
    language = $LanguageCode
    auto_number = [bool]$AutoNumber
}

$WorkspaceRoot = $Context.WorkspaceRoot
$BookRoot = $Context.BookRoot
$SourceRoot = if ($LanguageCode -eq "zh") {
    $BookRoot
} else {
    Join-Path $BookRoot ("03_translation\" + $LanguageCode)
}
$ObjectivePath = Join-Path $SourceRoot "00_brief\objective.md"
$ChapterRoot = Join-Path $SourceRoot "02_chapters"
$OutputRoot = Join-Path $BookRoot ("04_output\" + $LanguageCode)
$LogRoot = $Context.LogRoot
$BuildTempRoot = Join-Path $LogRoot ("_build_tmp_" + $LanguageCode)

function Get-FrontMatterValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [string]$Key
    )

    $Normalized = $Content -replace "`r", ""
    if (-not $Normalized.StartsWith("---`n")) {
        return $null
    }

    $Match = [regex]::Match($Normalized, "(?s)^---\n(.*?)\n---\n?")
    if (-not $Match.Success) {
        return $null
    }

    $Pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+?)\s*$"
    $ValueMatch = [regex]::Match($Match.Groups[1].Value, $Pattern)
    if (-not $ValueMatch.Success) {
        return $null
    }

    return $ValueMatch.Groups[1].Value.Trim().Trim('"')
}

function Get-MarkdownBodyText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Normalized = $Content -replace "`r", ""
    if ($Normalized.StartsWith("---`n")) {
        $Match = [regex]::Match($Normalized, "(?s)^---\n.*?\n---\n?")
        if ($Match.Success) {
            return $Normalized.Substring($Match.Length).Trim()
        }
    }

    return $Normalized.Trim()
}

function Get-TitlePageTitle {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title
    )

    $Normalized = $Title.Trim()
    if ($Normalized -match "[`r`n]") {
        return $Normalized
    }

    if ($Normalized.Length -ge 18 -and $Normalized -match "^(.*?[:：])\s*(.+)$") {
        return "$($Matches[1].Trim())`r`n$($Matches[2].Trim())"
    }

    return $Normalized
}

function Save-XmlUtf8 {
    param(
        [Parameter(Mandatory=$true)]
        [xml]$Document,

        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $Settings = New-Object System.Xml.XmlWriterSettings
    $Settings.Encoding = $Utf8NoBom
    $Settings.Indent = $false
    $Settings.OmitXmlDeclaration = $false

    $Writer = [System.Xml.XmlWriter]::Create($Path, $Settings)
    try {
        $Document.Save($Writer)
    }
    finally {
        $Writer.Dispose()
    }
}

function Load-XmlDocument {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $Document = New-Object System.Xml.XmlDocument
    $Document.PreserveWhitespace = $true
    $Document.Load($Path)
    return $Document
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Set-SectionHeaderFooter {
    param(
        [Parameter(Mandatory=$true)]
        [xml]$DocumentDoc,

        [Parameter(Mandatory=$true)]
        [System.Xml.XmlElement]$SectPrNode,

        [Parameter(Mandatory=$true)]
        [System.Xml.XmlNamespaceManager]$DocNs,

        [Parameter(Mandatory=$true)]
        [string]$DefaultHeaderRelId,

        [Parameter(Mandatory=$true)]
        [string]$FirstHeaderRelId,

        [Parameter(Mandatory=$true)]
        [string]$FooterRelId
    )

    @($SectPrNode.SelectNodes("w:headerReference", $DocNs)) | ForEach-Object { [void]$SectPrNode.RemoveChild($_) }
    @($SectPrNode.SelectNodes("w:footerReference", $DocNs)) | ForEach-Object { [void]$SectPrNode.RemoveChild($_) }

    $TitlePgNode = $SectPrNode.SelectSingleNode("w:titlePg", $DocNs)
    if ($null -eq $TitlePgNode) {
        $TitlePgNode = $DocumentDoc.CreateElement("w", "titlePg", $DocNs.LookupNamespace("w"))
        [void]$SectPrNode.PrependChild($TitlePgNode)
    }

    $FirstHeaderRef = $DocumentDoc.CreateElement("w", "headerReference", $DocNs.LookupNamespace("w"))
    [void]$FirstHeaderRef.SetAttribute("type", $DocNs.LookupNamespace("w"), "first")
    [void]$FirstHeaderRef.SetAttribute("id", $DocNs.LookupNamespace("r"), $FirstHeaderRelId)
    [void]$SectPrNode.PrependChild($FirstHeaderRef)

    $DefaultHeaderRef = $DocumentDoc.CreateElement("w", "headerReference", $DocNs.LookupNamespace("w"))
    [void]$DefaultHeaderRef.SetAttribute("type", $DocNs.LookupNamespace("w"), "default")
    [void]$DefaultHeaderRef.SetAttribute("id", $DocNs.LookupNamespace("r"), $DefaultHeaderRelId)
    [void]$SectPrNode.InsertAfter($DefaultHeaderRef, $FirstHeaderRef)

    $FirstFooterRef = $DocumentDoc.CreateElement("w", "footerReference", $DocNs.LookupNamespace("w"))
    [void]$FirstFooterRef.SetAttribute("type", $DocNs.LookupNamespace("w"), "first")
    [void]$FirstFooterRef.SetAttribute("id", $DocNs.LookupNamespace("r"), $FooterRelId)
    [void]$SectPrNode.InsertAfter($FirstFooterRef, $DefaultHeaderRef)

    $DefaultFooterRef = $DocumentDoc.CreateElement("w", "footerReference", $DocNs.LookupNamespace("w"))
    [void]$DefaultFooterRef.SetAttribute("type", $DocNs.LookupNamespace("w"), "default")
    [void]$DefaultFooterRef.SetAttribute("id", $DocNs.LookupNamespace("r"), $FooterRelId)
    [void]$SectPrNode.InsertAfter($DefaultFooterRef, $FirstFooterRef)
}

function Set-TitleParagraphText {
    param(
        [Parameter(Mandatory=$true)]
        [xml]$DocumentDoc,

        [Parameter(Mandatory=$true)]
        [System.Xml.XmlElement]$ParagraphNode,

        [Parameter(Mandatory=$true)]
        [System.Xml.XmlNamespaceManager]$DocNs,

        [Parameter(Mandatory=$true)]
        [string[]]$Lines
    )

    @($ParagraphNode.SelectNodes("w:r", $DocNs)) | ForEach-Object {
        [void]$ParagraphNode.RemoveChild($_)
    }

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $RunNode = $DocumentDoc.CreateElement("w", "r", $DocNs.LookupNamespace("w"))
        $RunProps = $DocumentDoc.CreateElement("w", "rPr", $DocNs.LookupNamespace("w"))
        $RunFonts = $DocumentDoc.CreateElement("w", "rFonts", $DocNs.LookupNamespace("w"))
        [void]$RunFonts.SetAttribute("hint", $DocNs.LookupNamespace("w"), "eastAsia")
        [void]$RunProps.AppendChild($RunFonts)
        [void]$RunNode.AppendChild($RunProps)

        $TextNode = $DocumentDoc.CreateElement("w", "t", $DocNs.LookupNamespace("w"))
        [void]$TextNode.SetAttribute("space", "http://www.w3.org/XML/1998/namespace", "preserve")
        $TextNode.InnerText = $Lines[$i]
        [void]$RunNode.AppendChild($TextNode)
        [void]$ParagraphNode.AppendChild($RunNode)

        if ($i -lt ($Lines.Count - 1)) {
            $BreakRun = $DocumentDoc.CreateElement("w", "r", $DocNs.LookupNamespace("w"))
            $BreakNode = $DocumentDoc.CreateElement("w", "br", $DocNs.LookupNamespace("w"))
            [void]$BreakRun.AppendChild($BreakNode)
            [void]$ParagraphNode.AppendChild($BreakRun)
        }
    }
}

function Update-DocxFormatting {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DocxPath,

        [Parameter(Mandatory=$true)]
        [string]$TempRoot,

        [Parameter(Mandatory=$true)]
        [string]$DocumentTitle
    )

    if (!(Test-Path $DocxPath)) {
        throw "Output document not found for style update."
    }

    $ExtractRoot = Join-Path $TempRoot "docx_style_patch"
    if (Test-Path $ExtractRoot) {
        Remove-Item $ExtractRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $ExtractRoot -Force | Out-Null

    [System.IO.Compression.ZipFile]::ExtractToDirectory($DocxPath, $ExtractRoot)

    $StylesPath = Join-Path $ExtractRoot "word\styles.xml"
    $SettingsPath = Join-Path $ExtractRoot "word\settings.xml"
    $DocumentPath = Join-Path $ExtractRoot "word\document.xml"
    $DocumentRelsPath = Join-Path $ExtractRoot "word\_rels\document.xml.rels"
    $ContentTypesPath = Join-Path $ExtractRoot "[Content_Types].xml"
    $HeaderPath = Join-Path $ExtractRoot "word\header1.xml"
    $FirstHeaderPath = Join-Path $ExtractRoot "word\header2.xml"
    $FooterPath = Join-Path $ExtractRoot "word\footer1.xml"
    if (!(Test-Path -LiteralPath $StylesPath)) {
        throw "word/styles.xml not found in generated document."
    }
    if (!(Test-Path -LiteralPath $SettingsPath)) {
        throw "word/settings.xml not found in generated document."
    }
    if (!(Test-Path -LiteralPath $DocumentPath)) {
        throw "word/document.xml not found in generated document."
    }
    if (!(Test-Path -LiteralPath $DocumentRelsPath)) {
        throw "word/_rels/document.xml.rels not found in generated document."
    }
    if (!(Test-Path -LiteralPath $ContentTypesPath)) {
        throw "[Content_Types].xml not found in generated document."
    }

    [xml]$StylesDoc = Load-XmlDocument -Path $StylesPath
    $Ns = New-Object System.Xml.XmlNamespaceManager($StylesDoc.NameTable)
    $Ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")

    $Heading1Node = $StylesDoc.SelectSingleNode("//w:style[@w:styleId='Heading1']", $Ns)
    if ($null -eq $Heading1Node) {
        throw "Heading1 style not found in generated document."
    }

    $NormalNode = $StylesDoc.SelectSingleNode("//w:style[@w:styleId='Normal']", $Ns)
    if ($null -eq $NormalNode) {
        throw "Normal style not found in generated document."
    }

    $PPrNode = $Heading1Node.SelectSingleNode("w:pPr", $Ns)
    if ($null -eq $PPrNode) {
        $PPrNode = $StylesDoc.CreateElement("w", "pPr", $Ns.LookupNamespace("w"))
        [void]$Heading1Node.PrependChild($PPrNode)
    }

    if ($null -eq $PPrNode.SelectSingleNode("w:pageBreakBefore", $Ns)) {
        $PageBreakNode = $StylesDoc.CreateElement("w", "pageBreakBefore", $Ns.LookupNamespace("w"))
        [void]$PPrNode.AppendChild($PageBreakNode)
    }

    $JcNode = $PPrNode.SelectSingleNode("w:jc", $Ns)
    if ($null -eq $JcNode) {
        $JcNode = $StylesDoc.CreateElement("w", "jc", $Ns.LookupNamespace("w"))
        [void]$PPrNode.AppendChild($JcNode)
    }
    [void]$JcNode.SetAttribute("val", $Ns.LookupNamespace("w"), "center")

    $NormalPPrNode = $NormalNode.SelectSingleNode("w:pPr", $Ns)
    if ($null -eq $NormalPPrNode) {
        $NormalPPrNode = $StylesDoc.CreateElement("w", "pPr", $Ns.LookupNamespace("w"))
        [void]$NormalNode.PrependChild($NormalPPrNode)
    }

    $NormalIndNode = $NormalPPrNode.SelectSingleNode("w:ind", $Ns)
    if ($null -eq $NormalIndNode) {
        $NormalIndNode = $StylesDoc.CreateElement("w", "ind", $Ns.LookupNamespace("w"))
        [void]$NormalPPrNode.AppendChild($NormalIndNode)
    }
    [void]$NormalIndNode.SetAttribute("firstLineChars", $Ns.LookupNamespace("w"), "200")

    Save-XmlUtf8 -Document $StylesDoc -Path $StylesPath

    [xml]$SettingsDoc = Load-XmlDocument -Path $SettingsPath
    $SettingsNs = New-Object System.Xml.XmlNamespaceManager($SettingsDoc.NameTable)
    $SettingsNs.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")

    $SettingsRoot = $SettingsDoc.SelectSingleNode("/w:settings", $SettingsNs)
    if ($null -eq $SettingsRoot) {
        throw "settings root node not found in generated document."
    }

    $UpdateFieldsNode = $SettingsRoot.SelectSingleNode("w:updateFields", $SettingsNs)
    if ($null -eq $UpdateFieldsNode) {
        $UpdateFieldsNode = $SettingsDoc.CreateElement("w", "updateFields", $SettingsNs.LookupNamespace("w"))
        [void]$SettingsRoot.AppendChild($UpdateFieldsNode)
    }
    [void]$UpdateFieldsNode.SetAttribute("val", $SettingsNs.LookupNamespace("w"), "true")

    Save-XmlUtf8 -Document $SettingsDoc -Path $SettingsPath

    $EscapedTitle = [System.Security.SecurityElement]::Escape($DocumentTitle)
    Write-Utf8Text -Path $HeaderPath -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p>
    <w:pPr>
      <w:pStyle w:val="Header" />
      <w:jc w:val="center" />
    </w:pPr>
    <w:r>
      <w:t xml:space="preserve">$EscapedTitle</w:t>
    </w:r>
  </w:p>
</w:hdr>
"@

    Write-Utf8Text -Path $FirstHeaderPath -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p>
    <w:pPr>
      <w:pStyle w:val="Header" />
      <w:jc w:val="center" />
    </w:pPr>
  </w:p>
</w:hdr>
"@

    Write-Utf8Text -Path $FooterPath -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p>
    <w:pPr>
      <w:pStyle w:val="Footer" />
      <w:jc w:val="center" />
    </w:pPr>
    <w:fldSimple w:instr=" PAGE ">
      <w:r>
        <w:rPr>
          <w:noProof />
        </w:rPr>
        <w:t>1</w:t>
      </w:r>
    </w:fldSimple>
  </w:p>
</w:ftr>
"@

    [xml]$ContentTypesDoc = Load-XmlDocument -Path $ContentTypesPath
    $CtNs = New-Object System.Xml.XmlNamespaceManager($ContentTypesDoc.NameTable)
    $CtNs.AddNamespace("ct", "http://schemas.openxmlformats.org/package/2006/content-types")
    $TypesRoot = $ContentTypesDoc.SelectSingleNode("/ct:Types", $CtNs)
    if ($null -eq $TypesRoot) {
        throw "content types root node not found in generated document."
    }

    if ($null -eq $ContentTypesDoc.SelectSingleNode("/ct:Types/ct:Override[@PartName='/word/header1.xml']", $CtNs)) {
        $HeaderOverride = $ContentTypesDoc.CreateElement("Override", $CtNs.LookupNamespace("ct"))
        [void]$HeaderOverride.SetAttribute("PartName", "/word/header1.xml")
        [void]$HeaderOverride.SetAttribute("ContentType", "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml")
        [void]$TypesRoot.AppendChild($HeaderOverride)
    }

    if ($null -eq $ContentTypesDoc.SelectSingleNode("/ct:Types/ct:Override[@PartName='/word/header2.xml']", $CtNs)) {
        $FirstHeaderOverride = $ContentTypesDoc.CreateElement("Override", $CtNs.LookupNamespace("ct"))
        [void]$FirstHeaderOverride.SetAttribute("PartName", "/word/header2.xml")
        [void]$FirstHeaderOverride.SetAttribute("ContentType", "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml")
        [void]$TypesRoot.AppendChild($FirstHeaderOverride)
    }

    if ($null -eq $ContentTypesDoc.SelectSingleNode("/ct:Types/ct:Override[@PartName='/word/footer1.xml']", $CtNs)) {
        $FooterOverride = $ContentTypesDoc.CreateElement("Override", $CtNs.LookupNamespace("ct"))
        [void]$FooterOverride.SetAttribute("PartName", "/word/footer1.xml")
        [void]$FooterOverride.SetAttribute("ContentType", "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml")
        [void]$TypesRoot.AppendChild($FooterOverride)
    }

    Save-XmlUtf8 -Document $ContentTypesDoc -Path $ContentTypesPath

    [xml]$DocRelsDoc = Load-XmlDocument -Path $DocumentRelsPath
    $RelNs = New-Object System.Xml.XmlNamespaceManager($DocRelsDoc.NameTable)
    $RelNs.AddNamespace("pr", "http://schemas.openxmlformats.org/package/2006/relationships")
    $RelsRoot = $DocRelsDoc.SelectSingleNode("/pr:Relationships", $RelNs)
    if ($null -eq $RelsRoot) {
        throw "document relationships root node not found in generated document."
    }

    $HeaderRelId = "rIdSageHeader"
    $FirstHeaderRelId = "rIdSageHeaderFirst"
    $FooterRelId = "rIdSageFooter"
    $HeaderRelType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
    $FooterRelType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"

    $HeaderRel = $DocRelsDoc.SelectSingleNode("/pr:Relationships/pr:Relationship[@Id='$HeaderRelId']", $RelNs)
    if ($null -eq $HeaderRel) {
        $HeaderRel = $DocRelsDoc.CreateElement("Relationship", $RelNs.LookupNamespace("pr"))
        [void]$HeaderRel.SetAttribute("Id", $HeaderRelId)
        [void]$HeaderRel.SetAttribute("Type", $HeaderRelType)
        [void]$HeaderRel.SetAttribute("Target", "header1.xml")
        [void]$RelsRoot.AppendChild($HeaderRel)
    }
    else {
        [void]$HeaderRel.SetAttribute("Type", $HeaderRelType)
        [void]$HeaderRel.SetAttribute("Target", "header1.xml")
    }

    $FirstHeaderRel = $DocRelsDoc.SelectSingleNode("/pr:Relationships/pr:Relationship[@Id='$FirstHeaderRelId']", $RelNs)
    if ($null -eq $FirstHeaderRel) {
        $FirstHeaderRel = $DocRelsDoc.CreateElement("Relationship", $RelNs.LookupNamespace("pr"))
        [void]$FirstHeaderRel.SetAttribute("Id", $FirstHeaderRelId)
        [void]$FirstHeaderRel.SetAttribute("Type", $HeaderRelType)
        [void]$FirstHeaderRel.SetAttribute("Target", "header2.xml")
        [void]$RelsRoot.AppendChild($FirstHeaderRel)
    }
    else {
        [void]$FirstHeaderRel.SetAttribute("Type", $HeaderRelType)
        [void]$FirstHeaderRel.SetAttribute("Target", "header2.xml")
    }

    $FooterRel = $DocRelsDoc.SelectSingleNode("/pr:Relationships/pr:Relationship[@Id='$FooterRelId']", $RelNs)
    if ($null -eq $FooterRel) {
        $FooterRel = $DocRelsDoc.CreateElement("Relationship", $RelNs.LookupNamespace("pr"))
        [void]$FooterRel.SetAttribute("Id", $FooterRelId)
        [void]$FooterRel.SetAttribute("Type", $FooterRelType)
        [void]$FooterRel.SetAttribute("Target", "footer1.xml")
        [void]$RelsRoot.AppendChild($FooterRel)
    }
    else {
        [void]$FooterRel.SetAttribute("Type", $FooterRelType)
        [void]$FooterRel.SetAttribute("Target", "footer1.xml")
    }

    Save-XmlUtf8 -Document $DocRelsDoc -Path $DocumentRelsPath

    [xml]$DocumentDoc = Load-XmlDocument -Path $DocumentPath
    $DocNs = New-Object System.Xml.XmlNamespaceManager($DocumentDoc.NameTable)
    $DocNs.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $DocNs.AddNamespace("r", "http://schemas.openxmlformats.org/officeDocument/2006/relationships")

    $BodyNode = $DocumentDoc.SelectSingleNode("/w:document/w:body", $DocNs)
    if ($null -eq $BodyNode) {
        throw "document body node not found in generated document."
    }

    $TitlePageText = Get-TitlePageTitle -Title $DocumentTitle
    $TitleLines = @(($TitlePageText -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($TitleLines.Count -gt 1) {
        $TitleParagraph = $BodyNode.SelectSingleNode("w:p[w:pPr/w:pStyle[@w:val='Title']][1]", $DocNs)
        if ($null -ne $TitleParagraph) {
            Set-TitleParagraphText -DocumentDoc $DocumentDoc -ParagraphNode $TitleParagraph -DocNs $DocNs -Lines $TitleLines
        }
    }

    $SectPrNode = $BodyNode.SelectSingleNode("w:sectPr", $DocNs)
    if ($null -eq $SectPrNode) {
        $SectPrNode = $DocumentDoc.SelectSingleNode("//w:sectPr", $DocNs)
    }
    if ($null -eq $SectPrNode) {
        $SectPrNode = $DocumentDoc.CreateElement("w", "sectPr", $DocNs.LookupNamespace("w"))
        [void]$BodyNode.AppendChild($SectPrNode)
    }

    $PageNumTypeNode = $SectPrNode.SelectSingleNode("w:pgNumType", $DocNs)
    if ($null -eq $PageNumTypeNode) {
        $PageNumTypeNode = $DocumentDoc.CreateElement("w", "pgNumType", $DocNs.LookupNamespace("w"))
        [void]$SectPrNode.AppendChild($PageNumTypeNode)
    }
    [void]$PageNumTypeNode.SetAttribute("start", $DocNs.LookupNamespace("w"), "1")

    Set-SectionHeaderFooter -DocumentDoc $DocumentDoc -SectPrNode $SectPrNode -DocNs $DocNs -DefaultHeaderRelId $HeaderRelId -FirstHeaderRelId $FirstHeaderRelId -FooterRelId $FooterRelId

    $HeadingParagraphs = @($BodyNode.SelectNodes("w:p[w:pPr/w:pStyle[@w:val='Heading1']]", $DocNs))
    $ParagraphNodes = @($BodyNode.SelectNodes("w:p", $DocNs))
    foreach ($HeadingParagraph in $HeadingParagraphs) {
        $HeadingIndex = [Array]::IndexOf($ParagraphNodes, $HeadingParagraph)
        if ($HeadingIndex -le 0) {
            continue
        }

        $PrevParagraph = $ParagraphNodes[$HeadingIndex - 1]
        $PrevParagraphPPr = $PrevParagraph.SelectSingleNode("w:pPr", $DocNs)
        if ($null -eq $PrevParagraphPPr) {
            $PrevParagraphPPr = $DocumentDoc.CreateElement("w", "pPr", $DocNs.LookupNamespace("w"))
            [void]$PrevParagraph.PrependChild($PrevParagraphPPr)
        }

        $ExistingPrevSectPr = $PrevParagraphPPr.SelectSingleNode("w:sectPr", $DocNs)
        if ($null -ne $ExistingPrevSectPr) {
            [void]$PrevParagraphPPr.RemoveChild($ExistingPrevSectPr)
        }

        $SectionBreakSectPr = $DocumentDoc.ImportNode($SectPrNode.CloneNode($true), $true)
        $TypeNode = $SectionBreakSectPr.SelectSingleNode("w:type", $DocNs)
        if ($null -eq $TypeNode) {
            $TypeNode = $DocumentDoc.CreateElement("w", "type", $DocNs.LookupNamespace("w"))
            [void]$SectionBreakSectPr.PrependChild($TypeNode)
        }
        [void]$TypeNode.SetAttribute("val", $DocNs.LookupNamespace("w"), "nextPage")

        $SectionPgNumType = $SectionBreakSectPr.SelectSingleNode("w:pgNumType", $DocNs)
        if ($null -ne $SectionPgNumType) {
            [void]$SectionBreakSectPr.RemoveChild($SectionPgNumType)
        }

        [void]$PrevParagraphPPr.AppendChild($SectionBreakSectPr)
    }

    Save-XmlUtf8 -Document $DocumentDoc -Path $DocumentPath

    Remove-Item -Path $DocxPath -Force -ErrorAction Stop
    [System.IO.Compression.ZipFile]::CreateFromDirectory($ExtractRoot, $DocxPath)
}

if (!(Test-Path $WorkspaceRoot)) {
    Fail-SageStep -Context $Context -Step "build" -Message "Workspace not found." -Data @{ workspace = $WorkspaceRoot; language = $LanguageCode }
    Write-Error "Workspace not found: $WorkspaceRoot"
    exit 1
}

if (!(Test-Path $SourceRoot)) {
    Fail-SageStep -Context $Context -Step "build" -Message "Language source root not found." -Data @{ source_root = $SourceRoot; language = $LanguageCode }
    Write-Error "Language source root not found: $SourceRoot"
    exit 1
}

if (!(Test-Path $ChapterRoot)) {
    Fail-SageStep -Context $Context -Step "build" -Message "Chapter folder not found." -Data @{ chapter_root = $ChapterRoot; language = $LanguageCode }
    Write-Error "Chapter folder not found: $ChapterRoot"
    exit 1
}

if (!(Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

if (!(Get-Command pandoc -ErrorAction SilentlyContinue)) {
    Fail-SageStep -Context $Context -Step "build" -Message "Pandoc not found." -Data @{ language = $LanguageCode }
    Write-Error "Pandoc not found."
    exit 1
}

$mdFiles = Get-ChildItem $ChapterRoot -Filter *.md |
    Where-Object { $_.Name -notmatch "^_" } |
    Sort-Object {
        if ($_.BaseName -match "^\d+") {
            [int]$matches[0]
        }
        else {
            9999
        }
    }

if ($mdFiles.Count -eq 0) {
    Fail-SageStep -Context $Context -Step "build" -Message "No markdown files found." -Data @{ chapter_root = $ChapterRoot; language = $LanguageCode }
    Write-Error "No markdown files found."
    exit 1
}

Write-Host "Found $($mdFiles.Count) chapter files."
Write-Host ""

foreach ($file in $mdFiles) {
    Write-Host "Adding: $($file.Name)"
}

$DocumentTitle = $BookName
$DocumentAuthor = "Generated by SageWrite"
if (Test-Path $ObjectivePath) {
    $ObjectiveRaw = Get-Content -LiteralPath $ObjectivePath -Raw
    $ObjectiveTitle = Get-FrontMatterValue -Content $ObjectiveRaw -Key "title"
    $ObjectiveAuthor = Get-FrontMatterValue -Content $ObjectiveRaw -Key "author"
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveTitle)) {
        $DocumentTitle = $ObjectiveTitle
    }
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveAuthor)) {
        $DocumentAuthor = $ObjectiveAuthor
    }
}

$TitlePageTitle = Get-TitlePageTitle -Title $DocumentTitle
$TitleYamlLines = @("title: |")
$TitleYamlLines += ($TitlePageTitle -split "`r?`n" | ForEach-Object { "  $_" })
$MetaContent = @(
    $TitleYamlLines
    "author: ""$DocumentAuthor"""
    "date: ""$(Get-Date -Format yyyy-MM-dd)"""
) -join "`r`n"

if (Test-Path $BuildTempRoot) {
    Remove-Item $BuildTempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $BuildTempRoot -Force | Out-Null

$BuildFiles = @()
foreach ($file in $mdFiles) {
    $Raw = Get-Content -LiteralPath $file.FullName -Raw
    $Body = Get-MarkdownBodyText -Content $Raw
    $TempPath = Join-Path $BuildTempRoot $file.Name
    Set-Content -LiteralPath $TempPath -Encoding utf8 -Value $Body
    $BuildFiles += $TempPath
}

$MetaFile = Join-Path $BuildTempRoot "_metadata.yaml"

$MetaContent | Set-Content $MetaFile -Encoding utf8

$OutputFile = Join-Path $OutputRoot "$BookName`_full.docx"
$BackupRoot = Join-Path $OutputRoot "back"
$BackupFile = $null

if (Test-Path $OutputFile) {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupFile = Join-Path $BackupRoot ("{0}_{1}{2}" -f $BookName, $Stamp, [System.IO.Path]::GetExtension($OutputFile))
    Copy-Item -LiteralPath $OutputFile -Destination $BackupFile -Force
    Write-Host ""
    Write-Host "Backed up existing output to:"
    Write-Host $BackupFile

    try {
        Remove-Item -LiteralPath $OutputFile -Force -ErrorAction Stop
    }
    catch {
        Fail-SageStep -Context $Context -Step "build" -Message "Existing output file is locked." -Data @{
            output = $OutputFile
            backup_output = $BackupFile
            error = $_.Exception.Message
            language = $LanguageCode
        }
        Write-Error "Existing output file is locked. Please close the Word document and try again: $OutputFile"
        exit 1
    }
}

$PandocArgs = @()
$PandocArgs += $BuildFiles
$PandocArgs += "--metadata-file=$MetaFile"
$PandocArgs += "-o"
$PandocArgs += $OutputFile
$PandocArgs += "--toc"
$PandocArgs += "--standalone"

if ($AutoNumber) {
    Write-Host ""
    Write-Host "Auto numbering enabled."
    $PandocArgs += "--number-sections"
}
else {
    Write-Host ""
    Write-Host "Auto numbering disabled."
}

try {
    & pandoc @PandocArgs
    $PandocExitCode = $LASTEXITCODE

    if ($PandocExitCode -ne 0) {
        throw "Pandoc exited with code $PandocExitCode."
    }

    if (!(Test-Path $OutputFile)) {
        throw "Pandoc build failed."
    }

    Update-DocxFormatting -DocxPath $OutputFile -TempRoot $BuildTempRoot -DocumentTitle $DocumentTitle

    Write-Host ""
    Write-Host "Build completed successfully:"
    Write-Host $OutputFile
}
catch {
    Fail-SageStep -Context $Context -Step "build" -Message "Build failed." -Data @{
        output = $OutputFile
        error = $_.Exception.Message
        language = $LanguageCode
    }
    Write-Error "Build failed: $_"
    exit 1
}
finally {
    Remove-Item $MetaFile -ErrorAction SilentlyContinue
    Remove-Item $BuildTempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-SageStep -Context $Context -Step "build" -State "success" -Message "Document build completed." -Data @{
    language = $LanguageCode
    source_root = $SourceRoot
    output = $OutputFile
    backup_output = $BackupFile
    chapter_count = $mdFiles.Count
    document_title = $DocumentTitle
    document_author = $DocumentAuthor
    auto_number = [bool]$AutoNumber
}
