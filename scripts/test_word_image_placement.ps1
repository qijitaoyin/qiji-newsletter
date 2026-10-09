param(
  [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$generatorPath = Join-Path $RepositoryRoot "scripts\generate_archive.ps1"
$generatorSource = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8
$sourceMatch = [regex]::Match($generatorSource, '\$defaultQijitaoyinSourceRoot\s*=\s*"(?<path>[^"]+)"')
if (-not $sourceMatch.Success) { throw "Cannot locate the canonical Word source setting." }
$canonicalSource = $sourceMatch.Groups["path"].Value
if (-not (Test-Path -LiteralPath $canonicalSource)) {
  throw "Canonical Word source is unavailable: $canonicalSource"
}

function Copy-TestFile {
  param([string]$RelativePath, [string]$TargetRoot)
  $source = Join-Path $RepositoryRoot $RelativePath
  if (-not (Test-Path -LiteralPath $source)) { return }
  $target = Join-Path $TargetRoot $RelativePath
  $parent = Split-Path -Parent $target
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  Copy-Item -LiteralPath $source -Destination $target -Force
}

function Move-FirstDocxImageBeforeBodyContent {
  param([string]$DocxPath)
  $stream = [System.IO.File]::Open($DocxPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
  $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
  try {
    $entry = $zip.GetEntry("word/document.xml")
    $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
    try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $ns.AddNamespace("a", "http://schemas.openxmlformats.org/drawingml/2006/main")
    $imageParagraph = $xml.SelectSingleNode("//w:body/w:p[.//a:blip][1]", $ns)
    $bodyMarkerText = -join @(0x3010, 0x6B63, 0x6587, 0x958B, 0x59CB, 0x3011 | ForEach-Object { [char]$_ })
    $bodyMarker = $null
    foreach ($paragraph in $xml.SelectNodes("//w:body/w:p", $ns)) {
      $textParts = @()
      foreach ($textNode in $paragraph.SelectNodes(".//w:t", $ns)) {
        $textParts += [string]$textNode.InnerText
      }
      if (($textParts -join "").Trim() -eq $bodyMarkerText) {
        $bodyMarker = $paragraph
        break
      }
    }
    if (-not $imageParagraph -or -not $bodyMarker) {
      throw "Image/body marker fixture is unavailable: $DocxPath"
    }
    $body = $bodyMarker.ParentNode
    [void]$body.RemoveChild($imageParagraph)
    [void]$body.InsertAfter($imageParagraph, $bodyMarker)
    $entry.Delete()
    $replacement = $zip.CreateEntry("word/document.xml")
    $writer = New-Object System.IO.StreamWriter($replacement.Open(), [System.Text.UTF8Encoding]::new($false))
    try { $xml.Save($writer) } finally { $writer.Dispose() }
  } finally {
    $zip.Dispose()
    $stream.Dispose()
  }
}

$tempBase = [System.IO.Path]::GetTempPath().TrimEnd('\')
$testRoot = Join-Path $tempBase ("qiji-word-image-test-" + [guid]::NewGuid().ToString("N"))
$sourceRoot = Join-Path $testRoot "source"
$sandboxRoot = Join-Path $testRoot "site"

try {
  New-Item -ItemType Directory -Force -Path $sourceRoot, $sandboxRoot | Out-Null
  foreach ($relativePath in @(
    "src\data\generatedArticles.ts",
    "src\data\reviewDraftArticles.ts",
    "src\data\generatedReview.ts",
    "src\data\publishState.json",
    "review-approvals.json"
  )) {
    Copy-TestFile $relativePath $sandboxRoot
  }

  $issue610 = Join-Path $sourceRoot "202610"
  $issue611 = Join-Path $sourceRoot "202611"
  New-Item -ItemType Directory -Force -Path $issue610, $issue611 | Out-Null
  $fixture = Get-ChildItem -LiteralPath (Join-Path $canonicalSource "202610") -File -Filter "2610-3-2*.docx" | Select-Object -First 1
  if (-not $fixture) { throw "Cannot find the 2610-3-2 body-image regression fixture." }
  Copy-Item -LiteralPath $fixture.FullName -Destination $issue610
  $preBodyFixturePath = Join-Path $issue611 ($fixture.Name -replace '^2610-', '2611-')
  Copy-Item -LiteralPath $fixture.FullName -Destination $preBodyFixturePath
  Move-FirstDocxImageBeforeBodyContent $preBodyFixturePath

  $pixabayAssetDir = Join-Path $sandboxRoot "public\assets\pixabay"
  New-Item -ItemType Directory -Force -Path $pixabayAssetDir | Out-Null
  [System.IO.File]::WriteAllBytes((Join-Path $pixabayAssetDir "pixabay-test.jpg"), [byte[]](0xFF, 0xD8, 0xFF, 0xD9))
  $pixabayStorePath = Join-Path $sandboxRoot "src\data\pixabayFallbackImages.json"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pixabayStorePath) | Out-Null
  $pixabayStore = @{
    version = 1
    policy = "nature-landscape-v2"
    usedImageIds = @("test")
    articles = @{
      "202610-2610-3-2" = @{
        imageId = "test"
        path = "/assets/pixabay/pixabay-test.jpg?v=1"
        caption = "Pixabay"
      }
    }
  }
  [System.IO.File]::WriteAllText($pixabayStorePath, ($pixabayStore | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))

  Remove-Item Env:PIXABAY_API_KEY -ErrorAction SilentlyContinue
  & $generatorPath -Root $sandboxRoot -SourceRoot $sourceRoot | Out-Host

  $draftPath = Join-Path $sandboxRoot "src\data\reviewDraftArticles.ts"
  $raw = Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
  $match = [regex]::Match($raw, 'export const reviewDraftArticles = (?<json>[\s\S]*?) satisfies Article\[\];')
  if (-not $match.Success) { throw "Cannot read generated review draft fixture." }
  $articles = [object[]]($match.Groups["json"].Value | ConvertFrom-Json)

  $bodyArticle = @($articles | Where-Object { $_.issueId -eq "202610" -and $_.sourceId -eq "2610-3-2" })[0]
  $bodyInlineImages = @($bodyArticle.contentBlocks | Where-Object { $_.type -eq "image" })
  if (
    -not $bodyArticle -or
    $bodyInlineImages.Count -ne 1 -or
    -not ([string]$bodyArticle.image).StartsWith("/assets/pixabay/") -or
    ([string]$bodyArticle.image -eq [string]$bodyInlineImages[0].src)
  ) {
    throw "A body image did not remain inline with separate Pixabay title artwork."
  }

  $preBodyArticle = @($articles | Where-Object { $_.issueId -eq "202611" -and $_.sourceId -eq "2611-3-2" })[0]
  $preBodyInlineImages = @($preBodyArticle.contentBlocks | Where-Object { $_.type -eq "image" })
  $knownImages = @($preBodyArticle.images | ForEach-Object { [string]$_.src })
  if (
    -not $preBodyArticle -or
    -not $preBodyArticle.image -or
    $knownImages -notcontains ([string]$preBodyArticle.image) -or
    $preBodyInlineImages.Count -ne 0
  ) {
    throw "An image before body content was not used exclusively as title artwork."
  }

  Write-Host "PASS: pre-body Word images become title artwork without duplication."
  Write-Host "PASS: in-body Word images remain inline and use separate Pixabay title artwork."
} finally {
  $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTestRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTestRoot)) {
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
  }
}
