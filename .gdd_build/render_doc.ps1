param(
    [Parameter(Mandatory=$true)][string]$SpecPath,
    [Parameter(Mandatory=$true)][string]$OutPath
)

$ErrorActionPreference = 'Stop'

$eastAsiaFont = -join ([char]0x5FAE, [char]0x8F6F, [char]0x96C5, [char]0x9ED1)  # Microsoft YaHei (CN)

function Esc($s) {
    return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;')
}

function FontPr($bold, $color, $sz) {
    $b = if ($bold) { '<w:b/>' } else { '<w:b w:val="0"/>' }
    $c = if ($color) { "<w:color w:val=`"$color`"/>" } else { '' }
    return "<w:rFonts w:ascii=`"Microsoft YaHei`" w:hAnsi=`"Microsoft YaHei`" w:eastAsia=`"$eastAsiaFont`" w:cs=`"Microsoft YaHei`"/><w:i w:val=`"0`"/><w:caps w:val=`"0`"/>$b$c<w:spacing w:val=`"0`"/><w:sz w:val=`"$sz`"/><w:szCs w:val=`"$sz`"/>"
}

function PPr($jc, $before, $after, $line, $indLeft, $firstLine) {
    $parts = @()
    $parts += "<w:spacing w:before=`"$before`" w:after=`"$after`" w:line=`"$line`" w:lineRule=`"auto`"/>"
    if ($jc) { $parts += "<w:jc w:val=`"$jc`"/>" }
    if ($indLeft -ne 0 -or $firstLine -ne 0) {
        $parts += "<w:ind w:left=`"$indLeft`" w:firstLine=`"$firstLine`"/>"
    }
    $parts += "<w:rPr>$(FontPr $false '' 21)</w:rPr>"
    return ($parts -join '')
}

function ParaXml($text, $bold, $color, $sz, $jc, $before, $after, $line, $indLeft, $firstLine) {
    $p = "<w:p><w:pPr>$(PPr $jc $before $after $line $indLeft $firstLine)</w:pPr>"
    $p += "<w:r><w:rPr>$(FontPr $bold $color $sz)</w:rPr><w:t xml:space=`"preserve`">$(Esc $text)</w:t></w:r></w:p>"
    return $p
}

function BulletXml($text) {
    $p = "<w:p><w:pPr>$(PPr '' 0 2 276 420 -210)</w:pPr>"
    $p += "<w:r><w:rPr>$(FontPr $false '' 21)</w:rPr><w:t xml:space=`"preserve`">$(Esc ([char]0x2022 + ' ' + $text))</w:t></w:r></w:p>"
    return $p
}

function TableXml($rows) {
    $nCols = $rows[0].Count
    $nRows = $rows.Count
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<w:tbl><w:tblPr>')
    [void]$sb.Append('<w:tblW w:w="5000" w:type="pct"/>')
    [void]$sb.Append('<w:tblBorders>')
    foreach ($side in 'top','left','bottom','right','insideH','insideV') {
        [void]$sb.Append("<w:$side w:val=`"single`" w:sz=`"4`" w:space=`"0`" w:color=`"8EA9DB`"/>")
    }
    [void]$sb.Append('</w:tblBorders>')
    [void]$sb.Append('<w:tblLayout w:type="autofit"/>')
    [void]$sb.Append('<w:tblCellMar><w:top w:w="40" w:type="dxa"/><w:left w:w="80" w:type="dxa"/><w:bottom w:w="40" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar>')
    [void]$sb.Append('</w:tblPr><w:tblGrid>')
    for ($c = 0; $c -lt $nCols; $c++) { [void]$sb.Append('<w:gridCol w:w="1200"/>') }
    [void]$sb.Append('</w:tblGrid>')

    for ($r = 0; $r -lt $nRows; $r++) {
        [void]$sb.Append('<w:tr>')
        for ($c = 0; $c -lt $nCols; $c++) {
            $txt = $rows[$r][$c]
            $isHeader = ($r -eq 0)
            $shd = if ($isHeader) { '<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>' } else { '' }
            [void]$sb.Append("<w:tc><w:tcPr><w:tcW w:w=`"0`" w:type=`"auto`"/>$shd<w:vAlign w:val=`"center`"/></w:tcPr>")
            $bold = $isHeader
            $color = if ($isHeader) { '1F4E79' } else { '' }
            $p = "<w:p><w:pPr>$(PPr $(if ($isHeader) {'center'} else {''}) 0 0 240 0 0)</w:pPr>"
            $p += "<w:r><w:rPr>$(FontPr $bold $color 18)</w:rPr><w:t xml:space=`"preserve`">$(Esc $txt)</w:t></w:r></w:p>"
            [void]$sb.Append($p)
            [void]$sb.Append('</w:tc>')
        }
        [void]$sb.Append('</w:tr>')
    }
    [void]$sb.Append('</w:tbl>')
    return $sb.ToString()
}

function PageBreakXml {
    return '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:br w:type="page"/></w:r></w:p>'
}

$lines = Get-Content -LiteralPath $SpecPath -Encoding UTF8
$body = New-Object System.Text.StringBuilder
$pendingTable = $null

foreach ($rawLine in $lines) {
    $line = $rawLine.TrimEnd("`r")
    if ($line -eq '') { continue }
    if ($line -eq '#PB') { [void]$body.Append((PageBreakXml)); continue }
    if ($line.StartsWith('#TB')) {
        $pendingTable = New-Object System.Collections.Generic.List[object]
        continue
    }
    if ($line -eq '#TE') {
        if ($null -ne $pendingTable -and $pendingTable.Count -gt 0) {
            $rows = @()
            foreach ($r in $pendingTable) { $rows += ,$r }
            [void]$body.Append((TableXml $rows))
            [void]$body.Append((ParaXml '' $false '' 21 '' 0 4 240 0 0))
        }
        $pendingTable = $null
        continue
    }
    if ($null -ne $pendingTable) {
        if ($line.StartsWith('#R|')) {
            $cells = $line.Substring(3) -split '\|'
            $pendingTable.Add($cells)
        }
        continue
    }
    if ($line.StartsWith('#T|')) { [void]$body.Append((ParaXml $line.Substring(3) $true 'C00000' 44 'center' 0 120 300 0 0)); continue }
    if ($line.StartsWith('#S|')) { [void]$body.Append((ParaXml $line.Substring(3) $true '595959' 28 'center' 240 240 300 0 0)); continue }
    if ($line.StartsWith('#M|')) { [void]$body.Append((ParaXml $line.Substring(3) $false '595959' 22 'center' 0 40 300 0 0)); continue }
    if ($line.StartsWith('#H1|')) { [void]$body.Append((ParaXml $line.Substring(4) $true '1F4E79' 32 '' 280 160 300 0 0)); continue }
    if ($line.StartsWith('#H2|')) { [void]$body.Append((ParaXml $line.Substring(4) $true '000000' 27 '' 200 120 300 0 0)); continue }
    if ($line.StartsWith('#H3|')) { [void]$body.Append((ParaXml $line.Substring(4) $true '1F4E79' 24 '' 160 80 300 0 0)); continue }
    if ($line.StartsWith('#B|')) { [void]$body.Append((BulletXml $line.Substring(3))); continue }
    if ($line.StartsWith('#P|')) { [void]$body.Append((ParaXml $line.Substring(3) $false '' 21 '' 0 100 300 0 0)); continue }
}

if ($null -ne $pendingTable -and $pendingTable.Count -gt 0) {
    $rows = @()
    foreach ($r in $pendingTable) { $rows += ,$r }
    [void]$body.Append((TableXml $rows))
    [void]$body.Append((ParaXml '' $false '' 21 '' 0 4 240 0 0))
}

$bodyXml = $body.ToString()

$documentXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<w:body>
$bodyXml
<w:sectPr>
<w:pgSz w:w="11906" w:h="16838"/>
<w:pgMar w:top="1247" w:right="1361" w:bottom="1247" w:left="1361" w:header="851" w:footer="992" w:gutter="0"/>
</w:sectPr>
</w:body>
</w:document>
"@

$contentTypes = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>
"@

$relsRoot = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
"@

$relsDoc = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
"@

$title = [System.IO.Path]::GetFileNameWithoutExtension($OutPath)
$core = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<dc:title>$(Esc $title)</dc:title>
<dc:creator>Game Design Team</dc:creator>
<dcterms:created xsi:type="dcterms:W3CDTF">2026-08-10T00:00:00Z</dcterms:created>
<dcterms:modified xsi:type="dcterms:W3CDTF">2026-08-10T00:00:00Z</dcterms:modified>
</cp:coreProperties>
"@

$app = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
<Application>Microsoft Office Word</Application>
<DocSecurity>0</DocSecurity>
<ScaleCrop>false</ScaleCrop>
<Company></Company>
<LinksUpToDate>false</LinksUpToDate>
<SharedDoc>false</SharedDoc>
<HyperlinksChanged>false</HyperlinksChanged>
<AppVersion>16.0000</AppVersion>
</Properties>
"@

$utf8 = New-Object System.Text.UTF8Encoding($false)
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("docx_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmpDir 'word\_rels') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmpDir 'docProps') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmpDir '_rels') | Out-Null

[System.IO.File]::WriteAllText((Join-Path $tmpDir '[Content_Types].xml'), $contentTypes, $utf8)
[System.IO.File]::WriteAllText((Join-Path $tmpDir '_rels\.rels'), $relsRoot, $utf8)
[System.IO.File]::WriteAllText((Join-Path $tmpDir 'word\document.xml'), $documentXml, $utf8)
[System.IO.File]::WriteAllText((Join-Path $tmpDir 'word\_rels\document.xml.rels'), $relsDoc, $utf8)
[System.IO.File]::WriteAllText((Join-Path $tmpDir 'docProps\core.xml'), $core, $utf8)
[System.IO.File]::WriteAllText((Join-Path $tmpDir 'docProps\app.xml'), $app, $utf8)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $OutPath) { Remove-Item -LiteralPath $OutPath -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($tmpDir, $OutPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

Remove-Item -LiteralPath $tmpDir -Recurse -Force
Write-Output "OK: $OutPath"
