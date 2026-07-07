Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$csv = Import-Csv -LiteralPath 'reports\word-normalize-latest.csv' | Where-Object { $_.status -eq 'normalized' }
$templateMarker = '【氣機導引電子報文章資料】'
$bodyMarker = '【正文開始】'
function ConvertTo-PlainText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
  return (($Text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '') -replace '\s+', ' ').Trim()
}
function New-TextParagraph([xml]$Xml, [string]$Text) {
  $p = $Xml.CreateElement('w', 'p', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
  $r = $Xml.CreateElement('w', 'r', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
  $t = $Xml.CreateElement('w', 't', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
  $t.InnerText = $Text
  $r.AppendChild($t) | Out-Null
  $p.AppendChild($r) | Out-Null
  return $p
}
function Get-TextRecords([xml]$Xml, $Ns) {
  $records = New-Object System.Collections.Generic.List[object]
  foreach ($p in $Xml.SelectNodes('//w:body/w:p', $Ns)) {
    $text = (($p.SelectNodes('.//w:t', $Ns) | ForEach-Object { $_.'#text' }) -join '')
    $text = ConvertTo-PlainText $text
    if ($text) { $records.Add(@{ Node=$p; Text=$text }) }
  }
  return $records.ToArray()
}
$count = 0
$skipped = 0
foreach ($row in $csv) {
  if (-not (Test-Path -LiteralPath $row.file)) { continue }
  $stream = [System.IO.File]::Open($row.file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
  try {
    $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
    try {
      $entry = $zip.GetEntry('word/document.xml')
      if (-not $entry) { continue }
      $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
      try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
      $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
      $ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')
      $body = $xml.SelectSingleNode('//w:body', $ns)
      $records = Get-TextRecords $xml $ns
      if ($records.Count -eq 0) { continue }
      if ($records[0].Text -eq $templateMarker) { $skipped++; continue }
      $templateIndex = -1
      for ($i=0; $i -lt $records.Count; $i++) { if ($records[$i].Text -eq $templateMarker) { $templateIndex = $i; break } }
      $bodyIndex = -1
      for ($i=0; $i -lt $records.Count; $i++) {
        if ($records[$i].Text -ne $templateMarker -and $records[$i].Text -ne $bodyMarker -and
            $records[$i].Text -notlike '文章分類：*' -and $records[$i].Text -notlike '文章標題：*' -and
            $records[$i].Text -notlike '作者：*' -and $records[$i].Text -notlike '日期：*' -and
            $records[$i].Text -notlike '圖片來源：*') { $bodyIndex = $i; break }
      }
      if ($templateIndex -lt 0 -or $bodyIndex -lt 0) { continue }
      $firstBodyNode = $records[$bodyIndex].Node
      $node = $body.FirstChild
      while ($node -and -not [object]::ReferenceEquals($node, $firstBodyNode)) {
        $next = $node.NextSibling
        if ($node.LocalName -eq 'p') { $body.RemoveChild($node) | Out-Null }
        $node = $next
      }
      $lines = @(
        $templateMarker,
        '',
        "文章分類：$($row.category)",
        "文章標題：$($row.title)",
        "作者：$($row.author)",
        "日期：$($row.date)",
        '圖片來源：',
        '',
        $bodyMarker
      )
      for ($i=0; $i -lt $lines.Count; $i++) {
        $body.InsertBefore((New-TextParagraph $xml $lines[$i]), $firstBodyNode) | Out-Null
      }
      $entry.Delete()
      $newEntry = $zip.CreateEntry('word/document.xml')
      $writer = New-Object System.IO.StreamWriter($newEntry.Open(), (New-Object System.Text.UTF8Encoding($false)))
      try { $xml.Save($writer) } finally { $writer.Dispose() }
      $count++
    } finally { $zip.Dispose() }
  } finally { $stream.Dispose() }
}
"fixed=$count skipped=$skipped"
