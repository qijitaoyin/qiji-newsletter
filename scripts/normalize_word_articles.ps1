param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$sourceRoot = Join-Path $Root "各期電子報"
$reportDir = Join-Path $Root "reports"
$generatedWordReviewPath = Join-Path $Root "src\data\generatedWordNormalizeReview.ts"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$templateMarker = "【氣機導引電子報文章資料】"
$bodyMarker = "【正文開始】"
$categoryRules = @(
  @{ Pattern = "編輯小語|覺能降臨"; Category = "編輯小語" },
  @{ Pattern = "如是我聞|疑義相與析|群組討論"; Category = "如是我聞" },
  @{ Pattern = "體證道德經|道德經|老子"; Category = "體證道德經" },
  @{ Pattern = "導引按蹻|治療|骨盆"; Category = "導引按蹻" },
  @{ Pattern = "練功筆記|功夫|無極"; Category = "練功筆記" },
  @{ Pattern = "導引香道|香之物語|沉香|識香|五感香道|妙觀品藏香"; Category = "導引香道" },
  @{ Pattern = "圖靈集|AI|NPC"; Category = "圖靈集" },
  @{ Pattern = "心田集"; Category = "心田集" },
  @{ Pattern = "觀行錄"; Category = "觀行錄" },
  @{ Pattern = "股海人生|貨、幣|資產負債|週期"; Category = "股海人生" },
  @{ Pattern = "導引采風|采風錄"; Category = "導引采風錄" },
  @{ Pattern = "同頻共振"; Category = "同頻共振" },
  @{ Pattern = "身體書寫"; Category = "身體書寫" },
  @{ Pattern = "山腳下的蘆葦"; Category = "山腳下的蘆葦" }
)

function ConvertTo-PlainText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $value = [System.Net.WebUtility]::HtmlDecode($Text)
  $value = $value -replace "[\x00-\x08\x0B\x0C\x0E-\x1F]", ""
  $value = $value -replace "\s+", " "
  return $value.Trim()
}

function Limit-Text {
  param([string]$Text, [int]$Length = 220)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $value = $Text.Trim()
  if ($value.Length -le $Length) { return $value }
  return "$($value.Substring(0, $Length))..."
}

function Normalize-Name {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $value = $Text.Trim()
  $value = $value -replace "^◎\s*", ""
  if ($value -match "^[\u4e00-\u9fff](\s+[\u4e00-\u9fff]){1,4}$") {
    return ($value -replace "\s+", "")
  }
  $value = $value -replace "^(文|整理|撰文|作者|編輯|口述|彙整)[／/：:]\s*", ""
  return ($value -replace "\s+", " ").Trim()
}

function Test-AuthorLine {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $value = $Text.Trim()
  if ($value.Length -gt 64) { return $false }
  if ($value -match "[。！？；]$") { return $false }
  if ($value -match "^◎\s*[\u4e00-\u9fff]{2,4}$") { return $true }
  if ($value -match "^(文|整理|撰文|作者|編輯|口述|彙整)[／/：:]") { return $true }
  if ($value -match "莫仁維|張尊堡|Richard\s+Moh|Bob\s+Chang") { return $true }
  if ($value -match "^[\u4e00-\u9fff](\s+[\u4e00-\u9fff]){1,4}$") { return $true }
  if ($value -match "^[\u4e00-\u9fff]{2,4}([、，,／/\s和與][\u4e00-\u9fff]{2,4}){0,4}$") { return $true }
  return $false
}

function Get-CategoryInfo {
  param([string]$Title)
  foreach ($rule in $categoryRules) {
    if ($Title -match $rule.Pattern) { return $rule.Category }
  }
  return "專欄文章"
}

function Get-SeriesHeaderInfo {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  $value = $Text.Trim("【】「」 ")
  if ($value -notmatch "・之[一二三四五六七八九十百]+$") { return $null }
  $marker = [regex]::Match($value, "之[一二三四五六七八九十百]+$")
  if (-not $marker.Success) { return $null }
  $seriesTitle = $value.Substring(0, $marker.Index).Trim("・／/ -_　")
  $seriesTitle = $seriesTitle -replace "^每月專題[／/]", ""
  $seriesTitle = $seriesTitle -replace "^20\d{2}(?=新春團拜)", ""
  $seriesTitle = $seriesTitle.Trim("・／/ -_　")
  if (-not $seriesTitle) { return $null }
  $baseCategory = Get-CategoryInfo $seriesTitle
  $category = if ($baseCategory -eq $seriesTitle) { $seriesTitle } else { "$baseCategory/$seriesTitle" }
  return @{
    SeriesTitle = $seriesTitle
    Part = $marker.Value
    Category = $category
  }
}

function Get-LegacyHeaderSuggestion {
  param([string[]]$Texts, [string]$IssueId)
  if (-not $Texts -or $Texts.Count -lt 2) { return $null }

  $line0 = ($Texts[0] -as [string]).Trim()
  if (-not $line0) { return $null }
  if ($line0 -match "目錄|來源頁面|^https?://") { return $null }

  $line1 = ($Texts[1] -as [string]).Trim()
  if (-not $line1) { return $null }

  $categoryText = $line0
  $series = Get-SeriesHeaderInfo $line0
  if ($series) {
    $categoryText = $series.Category
  } else {
    if ($line0 -match "如是我[.．・·]聞") {
      $categoryText = "如是我聞"
    } elseif ($categoryText -match "[・·•]") {
      $categoryText = ($categoryText -split "[・·•]")[0]
    }
    if ($categoryText -match "第\d+期") {
      $categoryText = ($categoryText -split "第\d+期")[0]
    }
    if ($line0 -match "(之[一二三四五六七八九十百]+)") {
      $categoryText = $categoryText -replace "[／/・·•\s-]*之[一二三四五六七八九十百]+.*$", ""
    }
  }

  $categoryText = $categoryText -replace "如是我[.．・·]聞", "如是我聞"
  $categoryText = $categoryText.Trim("【】「」／/・·• -_　")
  if (-not $categoryText) { return $null }

  $title = $line1.Trim("【】「」 ")

  $author = ""
  if ($Texts.Count -ge 3 -and (Test-AuthorLine $Texts[2])) {
    $author = Normalize-Name $Texts[2]
  }

  $preview = ""
  foreach ($candidate in @($Texts | Select-Object -Skip 2)) {
    $value = ($candidate -as [string]).Trim()
    if (-not $value) { continue }
    if ($value -eq $title -or $value -eq $line0 -or (Test-AuthorLine $value)) { continue }
    if ($value -match "^(圖片來源|圖片標題|照片來源|圖說)[／/:：]") { continue }
    $preview = Limit-Text $value 260
    break
  }

  $category = if ($categoryText -match "/") { $categoryText } else { Get-CategoryInfo $categoryText }
  if ($category -eq "專欄文章" -and $categoryText -ne "專欄文章") {
    $category = $categoryText
  }

  return @{
    Category = $category
    Title = $title
    Author = $author
    Date = Get-DateFromIssueId $IssueId
    Preview = $preview
  }
}

function Get-IssueIdForFile {
  param([System.IO.FileInfo]$File)
  $dir = $File.Directory
  while ($dir -and $dir.FullName.StartsWith($sourceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    if ($dir.Name -match "20\d{4}") { return $Matches[0] }
    $dir = $dir.Parent
  }
  return ""
}

function Get-DateFromIssueId {
  param([string]$IssueId)
  if ($IssueId -match "^(20\d{2})(\d{2})$") {
    return "$($Matches[1]).$($Matches[2]).10"
  }
  return ""
}

function Open-Docx {
  param([string]$Path, [switch]$Write)
  $access = if ($Write) { [System.IO.FileAccess]::ReadWrite } else { [System.IO.FileAccess]::Read }
  $mode = if ($Write) { [System.IO.Compression.ZipArchiveMode]::Update } else { [System.IO.Compression.ZipArchiveMode]::Read }
  $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, $access, [System.IO.FileShare]::ReadWrite)
  return @{
    Stream = $stream
    Zip = New-Object System.IO.Compression.ZipArchive($stream, $mode, $false)
  }
}

function Read-DocumentXml {
  param($Zip)
  $entry = $Zip.GetEntry("word/document.xml")
  if (-not $entry) { return $null }
  $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
  try { return [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Save-DocumentXml {
  param($Zip, [xml]$Xml)
  $entry = $Zip.GetEntry("word/document.xml")
  if (-not $entry) { throw "word/document.xml not found" }
  $entry.Delete()
  $newEntry = $Zip.CreateEntry("word/document.xml")
  $writer = New-Object System.IO.StreamWriter($newEntry.Open(), (New-Object System.Text.UTF8Encoding($false)))
  try { $Xml.Save($writer) } finally { $writer.Dispose() }
}

function Get-ParagraphRecords {
  param([xml]$Xml, [System.Xml.XmlNamespaceManager]$Ns)
  $records = New-Object System.Collections.Generic.List[object]
  foreach ($p in $Xml.SelectNodes("//w:body/w:p", $Ns)) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($node in $p.SelectNodes(".//w:t|.//w:tab|.//w:br", $Ns)) {
      if ($node.LocalName -eq "tab" -or $node.LocalName -eq "br") {
        $parts.Add(" ")
      } else {
        $parts.Add($node.InnerText)
      }
    }
    $text = ConvertTo-PlainText ($parts -join "")
    if ($text) { $records.Add(@{ Node = $p; Text = $text }) }
  }
  return $records.ToArray()
}

function New-TextParagraph {
  param([xml]$Xml, [string]$Text)
  $p = $Xml.CreateElement("w", "p", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
  $r = $Xml.CreateElement("w", "r", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
  $t = $Xml.CreateElement("w", "t", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
  if ($Text -match "^\s|\s$") {
    $space = $Xml.CreateAttribute("xml", "space", "http://www.w3.org/XML/1998/namespace")
    $space.Value = "preserve"
    $t.Attributes.Append($space) | Out-Null
  }
  $t.InnerText = $Text
  $r.AppendChild($t) | Out-Null
  $p.AppendChild($r) | Out-Null
  return $p
}

function Insert-Before {
  param([System.Xml.XmlNode]$Parent, [System.Xml.XmlNode]$NewNode, [System.Xml.XmlNode]$RefNode)
  $Parent.InsertBefore($NewNode, $RefNode) | Out-Null
}

function Analyze-Docx {
  param([System.IO.FileInfo]$File)
  $opened = Open-Docx $File.FullName
  try {
    $xml = Read-DocumentXml $opened.Zip
    if (-not $xml) { return @{ Status = "error"; Reason = "missing-document-xml" } }
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $records = Get-ParagraphRecords $xml $ns
    $texts = @($records | ForEach-Object { $_.Text })
    if ($texts.Count -eq 0) { return @{ Status = "error"; Reason = "empty-document" } }
    if ($texts[0] -eq $templateMarker) { return @{ Status = "skipped"; Reason = "already-standard" } }
    if ($File.BaseName -match "目錄|menu|index" -or $texts[0] -match "目錄|來源頁面") {
      return @{ Status = "skipped"; Reason = "table-of-contents" }
    }

    $issueId = Get-IssueIdForFile $File
    $date = Get-DateFromIssueId $issueId
    $series = Get-SeriesHeaderInfo $texts[0]
    if ($series -and $texts.Count -ge 4 -and (Test-AuthorLine $texts[2])) {
      $subtitle = $texts[1].Trim("【】「」 ")
      if ($subtitle) {
        return @{
          Status = "normalize"
          Rule = "series-heading"
          Category = $series.Category
          Title = $subtitle
          Author = Normalize-Name $texts[2]
          Date = $date
          RemoveCount = 3
          Preview = $texts[3]
        }
      }
    }

    $suggestion = Get-LegacyHeaderSuggestion $texts $issueId
    if ($suggestion) {
      return @{
        Status = "review"
        Reason = "needs-confirmation"
        Rule = "legacy-heading-suggestion"
        Category = $suggestion.Category
        Title = $suggestion.Title
        Author = $suggestion.Author
        Date = $suggestion.Date
        Preview = $suggestion.Preview
        FirstLines = @($texts | Select-Object -First 6)
      }
    }

    return @{
      Status = "review"
      Reason = "unsupported-legacy-structure"
      FirstLines = @($texts | Select-Object -First 6)
    }
  } catch {
    return @{ Status = "error"; Reason = $_.Exception.Message }
  } finally {
    if ($opened.Zip) { $opened.Zip.Dispose() }
    if ($opened.Stream) { $opened.Stream.Dispose() }
  }
}

function Normalize-Docx {
  param([System.IO.FileInfo]$File, [hashtable]$Plan)
  $opened = Open-Docx $File.FullName -Write
  try {
    $xml = Read-DocumentXml $opened.Zip
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $body = $xml.SelectSingleNode("//w:body", $ns)
    $records = Get-ParagraphRecords $xml $ns
    if ($records.Count -eq 0) { throw "empty-document" }
    $firstBodyNode = $records[0].Node

    $metaLines = @(
      $templateMarker,
      "",
      "文章分類：$($Plan.Category)",
      "文章標題：$($Plan.Title)",
      "作者：$($Plan.Author)",
      "日期：$($Plan.Date)",
      "圖片來源：",
      "",
      $bodyMarker
    )
    for ($i = 0; $i -lt $metaLines.Count; $i++) {
      Insert-Before $body (New-TextParagraph $xml $metaLines[$i]) $firstBodyNode
    }
    for ($i = 0; $i -lt $Plan.RemoveCount -and $i -lt $records.Count; $i++) {
      $node = $records[$i].Node
      if ($node.ParentNode) { $node.ParentNode.RemoveChild($node) | Out-Null }
    }
    Save-DocumentXml $opened.Zip $xml
  } finally {
    if ($opened.Zip) { $opened.Zip.Dispose() }
    if ($opened.Stream) { $opened.Stream.Dispose() }
  }
}

$files = Get-ChildItem -LiteralPath $sourceRoot -Recurse -Filter "*.docx" |
  Where-Object {
    $_.Name -notlike "~$*" -and
    $_.Name -notlike "._*" -and
    $_.Length -gt 0
  }

$results = New-Object System.Collections.Generic.List[object]
foreach ($file in $files) {
  $plan = Analyze-Docx $file
  $item = [ordered]@{
    file = $file.FullName
    issueId = Get-IssueIdForFile $file
    status = $plan.Status
    reason = $plan.Reason
    rule = $plan.Rule
    category = $plan.Category
    title = $plan.Title
    author = $plan.Author
    date = $plan.Date
    preview = Limit-Text $plan.Preview 260
    firstLines = @($plan.FirstLines | ForEach-Object { Limit-Text $_ 260 })
  }
  if ($plan.Status -eq "normalize" -and -not $DryRun) {
    try {
      Normalize-Docx $file $plan
      $item.status = "normalized"
    } catch {
      $item.status = "error"
      $item.reason = $_.Exception.Message
    }
  }
  $results.Add([pscustomobject]$item)
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$jsonPath = Join-Path $reportDir "word-normalize-$timestamp.json"
$csvPath = Join-Path $reportDir "word-normalize-$timestamp.csv"
$latestJsonPath = Join-Path $reportDir "word-normalize-latest.json"
$latestCsvPath = Join-Path $reportDir "word-normalize-latest.csv"

$results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8
$results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$results | Export-Csv -LiteralPath $latestCsvPath -NoTypeInformation -Encoding UTF8

$wordReviewJson = $results | ConvertTo-Json -Depth 10
$wordReviewContent = @"
export const generatedWordNormalizeItems = $wordReviewJson;
"@
Set-Content -LiteralPath $generatedWordReviewPath -Encoding UTF8 -Value $wordReviewContent

$summary = $results | Group-Object status | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Host "Word normalization report:"
Write-Host "  $jsonPath"
Write-Host "  $csvPath"
Write-Host "Summary: $($summary -join ', ')"

