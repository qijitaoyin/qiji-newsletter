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

function Move-FirstDocxImageBeforeBodyMarker {
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
    [void]$body.InsertBefore($imageParagraph, $bodyMarker)
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
    "review-approvals.json",
    ".cache\article-import-cache.json"
  )) {
    Copy-TestFile $relativePath $sandboxRoot
  }

  $issue301 = Join-Path $sourceRoot "202301"
  $issue610 = Join-Path $sourceRoot "202610"
  $issue611 = Join-Path $sourceRoot "202611"
  $issue612 = Join-Path $sourceRoot "202612"
  New-Item -ItemType Directory -Force -Path $issue301, $issue610, $issue611, $issue612 | Out-Null
  $legacyCacheFixture = Get-ChildItem -LiteralPath (Join-Path $canonicalSource "202301") -File -Filter "2301-2-3*.docx" | Select-Object -First 1
  if (-not $legacyCacheFixture) { throw "Cannot find the 2301-2-3 legacy cached-image regression fixture." }
  Copy-Item -LiteralPath $legacyCacheFixture.FullName -Destination $issue301
  $fixture = Get-ChildItem -LiteralPath (Join-Path $canonicalSource "202610") -File -Filter "2610-3-2*.docx" | Select-Object -First 1
  if (-not $fixture) { throw "Cannot find the 2610-3-2 body-image regression fixture." }
  Copy-Item -LiteralPath $fixture.FullName -Destination $issue610
  # A loose issue-folder image may belong to another article. Even when its
  # filename resembles this source id, it must never become title artwork.
  [System.IO.File]::WriteAllBytes((Join-Path $issue610 "2610-3-2.jpg"), [byte[]](0xFF, 0xD8, 0xFF, 0xD9))
  $preBodyFixturePath = Join-Path $issue611 ($fixture.Name -replace '^2610-', '2611-')
  Copy-Item -LiteralPath $fixture.FullName -Destination $preBodyFixturePath
  Move-FirstDocxImageBeforeBodyMarker $preBodyFixturePath

  $tiffFixture = Get-ChildItem -LiteralPath (Join-Path $canonicalSource "202611") -File -Filter "2611-3-2*.docx" | Select-Object -First 1
  if (-not $tiffFixture) { throw "Cannot find the 2611-3-2 TIFF image regression fixture." }
  $tiffFixturePath = Join-Path $issue612 ($tiffFixture.Name -replace '^2611-', '2612-')
  Copy-Item -LiteralPath $tiffFixture.FullName -Destination $tiffFixturePath

  $sameIssueFixture = Get-ChildItem -LiteralPath (Join-Path $canonicalSource "202611") -File -Filter "2611-3-5*.docx" | Select-Object -First 1
  if (-not $sameIssueFixture) { throw "Cannot find the 2611-3-5 cross-article image fixture." }
  $sameIssueFixturePath = Join-Path $issue612 ($sameIssueFixture.Name -replace '^2611-', '2612-')
  Copy-Item -LiteralPath $sameIssueFixture.FullName -Destination $sameIssueFixturePath

  $pixabayAssetDir = Join-Path $sandboxRoot "public\assets\pixabay"
  New-Item -ItemType Directory -Force -Path $pixabayAssetDir | Out-Null
  [System.IO.File]::WriteAllBytes((Join-Path $pixabayAssetDir "pixabay-test.jpg"), [byte[]](0xFF, 0xD8, 0xFF, 0xD9))
  $pixabayStorePath = Join-Path $sandboxRoot "src\data\pixabayFallbackImages.json"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pixabayStorePath) | Out-Null
  $pixabayStore = @{
    version = 1
    policy = "nature-landscape-v3"
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
  if (Test-Path -LiteralPath (Join-Path $sandboxRoot "public\assets\articles\202610\202610-img-001.jpg")) {
    throw "A loose issue-folder image was copied and could be assigned across articles."
  }

  $legacyCacheArticle = @($articles | Where-Object { $_.issueId -eq "202301" -and $_.sourceId -eq "2301-2-3" })[0]
  if (
    -not $legacyCacheArticle -or
    ([string]$legacyCacheArticle.image -match '^/assets/articles/202301/202301-img-\d{3}\.')
  ) {
    throw "A cached cross-article issue image was not removed."
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

  $tiffArticle = @($articles | Where-Object { $_.issueId -eq "202612" -and $_.sourceId -eq "2612-3-2" })[0]
  $tiffInlineImages = @($tiffArticle.contentBlocks | Where-Object { $_.type -eq "image" })
  if (
    -not $tiffArticle -or
    $tiffInlineImages.Count -ne 2 -or
    @($tiffInlineImages | Where-Object { [string]$_.src -notmatch '\.png(?:\?|$)' }).Count -ne 0
  ) {
    throw "Images after the body marker were not retained inline or TIFF conversion failed."
  }

  $sameIssueArticle = @($articles | Where-Object { $_.issueId -eq "202612" -and $_.sourceId -eq "2612-3-5" })[0]
  $firstArticlePaths = @($tiffArticle.images | ForEach-Object { ([string]$_.src -split '\?')[0] })
  $secondArticlePaths = @($sameIssueArticle.images | ForEach-Object { ([string]$_.src -split '\?')[0] })
  $collisions = @($firstArticlePaths | Where-Object { $secondArticlePaths -contains $_ })
  if (
    -not $sameIssueArticle -or
    $secondArticlePaths.Count -eq 0 -or
    $collisions.Count -ne 0 -or
    @($firstArticlePaths | Where-Object { $_ -notmatch '/202612-2612-3-2-img-\d{3}\.' }).Count -ne 0 -or
    @($secondArticlePaths | Where-Object { $_ -notmatch '/202612-2612-3-5-img-\d{3}\.' }).Count -ne 0
  ) {
    throw "Word images from separate articles can overwrite or share an output path."
  }

  Write-Host "PASS: pre-body Word images become title artwork without duplication."
  Write-Host "PASS: images after the body marker remain inline and use separate title artwork."
  Write-Host "PASS: loose issue-folder images cannot become cross-article title artwork."
  Write-Host "PASS: cached cross-article issue images are removed before fallback selection."
  Write-Host "PASS: TIFF Word images are converted to browser-compatible PNG files."
  Write-Host "PASS: every Word article uses deterministic article-scoped image paths."
} finally {
  $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTestRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTestRoot)) {
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
  }
}
