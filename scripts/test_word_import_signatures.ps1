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

function Invoke-TestImport {
  param([string]$Root, [string]$SourceRoot)
  & (Join-Path $RepositoryRoot "scripts\generate_archive.ps1") -Root $Root -SourceRoot $SourceRoot | Out-Host
  return Get-Content -LiteralPath (Join-Path $Root "public\data\import-changed-files.json") -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Convert-TestCacheToLegacyFormat {
  param([string]$Root)
  $cachePath = Join-Path $Root ".cache\article-import-cache.json"
  $cache = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($entry in @($cache.entries)) {
    foreach ($name in @("contentStructureHash", "contentArticleHash", "publishedEquivalentSignature")) {
      if ($entry.signature.PSObject.Properties[$name]) {
        $entry.signature.PSObject.Properties.Remove($name)
      }
    }
  }
  [System.IO.File]::WriteAllText($cachePath, ($cache | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

function Set-TestLegacyCacheHeadingToParagraph {
  param([string]$Root, [string]$IssueId)
  $cachePath = Join-Path $Root ".cache\article-import-cache.json"
  $cache = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $entry = @($cache.entries | Where-Object { [string]$_.signature.key -match "^$([regex]::Escape($IssueId))[\\/]" }) | Select-Object -First 1
  if (-not $entry) { throw "Cannot find cache entry for issue $IssueId." }
  $block = @($entry.article.contentBlocks | Where-Object { $_.type -eq "heading" }) | Select-Object -First 1
  if (-not $block) { throw "Cannot find cached heading block for issue $IssueId." }
  $block.type = "paragraph"
  if ($block.PSObject.Properties["level"]) {
    $block.PSObject.Properties.Remove("level")
  }
  [System.IO.File]::WriteAllText($cachePath, ($cache | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
  return [string]$block.text
}

function Remove-TestIssueFromArticleModule {
  param([string]$Path, [string]$ArticleExport, [string]$IssueExport, [string]$IssueId)
  $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $articleMatch = [regex]::Match($source, "export const $ArticleExport = (?<json>[\s\S]*?) satisfies Article\[\];")
  $issueMatch = [regex]::Match($source, "export const $IssueExport = (?<json>[\s\S]*?) satisfies IssueArchive\[\];")
  if (-not $articleMatch.Success -or -not $issueMatch.Success) { throw "Cannot parse test article module." }
  $parsedArticles = $articleMatch.Groups["json"].Value | ConvertFrom-Json
  $parsedIssues = $issueMatch.Groups["json"].Value | ConvertFrom-Json
  $articles = @($parsedArticles | Where-Object { [string]$_.issueId -ne $IssueId })
  $issues = @($parsedIssues | Where-Object { [string]$_.id -ne $IssueId })
  $articlesJson = ConvertTo-Json -InputObject $articles -Depth 20
  $issuesJson = ConvertTo-Json -InputObject $issues -Depth 20
  $content = @"
import type { Article, IssueArchive } from "./articles";

export const $ArticleExport = $articlesJson satisfies Article[];

export const $IssueExport = $issuesJson satisfies IssueArchive[];
"@
  [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
}

function Set-FirstStyledParagraphStyle {
  param([string]$DocxPath, [string]$StyleId)
  $stream = [System.IO.File]::Open($DocxPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
  $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
  try {
    $entry = $zip.GetEntry("word/document.xml")
    $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
    try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $paragraph = $xml.SelectSingleNode("//w:body/w:p[normalize-space(.//w:t) != '' and ./w:pPr/w:pStyle]", $ns)
    if (-not $paragraph) { throw "Fixture has no styled paragraph: $DocxPath" }
    $text = (($paragraph.SelectNodes(".//w:t", $ns) | ForEach-Object { $_.InnerText }) -join "").Trim()
    $style = $paragraph.SelectSingleNode("./w:pPr/w:pStyle", $ns)
    $originalStyleId = $style.GetAttribute("val", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $style.SetAttribute("val", "http://schemas.openxmlformats.org/wordprocessingml/2006/main", $StyleId)
    $entry.Delete()
    $replacement = $zip.CreateEntry("word/document.xml")
    $writer = New-Object System.IO.StreamWriter($replacement.Open(), [System.Text.UTF8Encoding]::new($false))
    try { $xml.Save($writer) } finally { $writer.Dispose() }
    return @{ text = $text; originalStyleId = $originalStyleId }
  } finally {
    $zip.Dispose()
    $stream.Dispose()
  }
}

function Add-DocxPackageMetadataNoise {
  param([string]$DocxPath)
  $stream = [System.IO.File]::Open($DocxPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
  $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
  try {
    $entry = $zip.GetEntry("docProps/core.xml")
    $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
    try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $entry.Delete()
    $replacement = $zip.CreateEntry("docProps/core.xml")
    $writer = New-Object System.IO.StreamWriter($replacement.Open(), [System.Text.UTF8Encoding]::new($false))
    try { $writer.Write($content + " ") } finally { $writer.Dispose() }
  } finally {
    $zip.Dispose()
    $stream.Dispose()
  }
}

function Add-FirstStyledParagraphTextSuffix {
  param([string]$DocxPath, [string]$Suffix)
  $stream = [System.IO.File]::Open($DocxPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
  $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
  try {
    $entry = $zip.GetEntry("word/document.xml")
    $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
    try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $textNode = $xml.SelectSingleNode("//w:body/w:p[normalize-space(.//w:t) != '' and ./w:pPr/w:pStyle]//w:t[1]", $ns)
    if (-not $textNode) { throw "Fixture has no styled paragraph text: $DocxPath" }
    $textNode.InnerText = $textNode.InnerText + $Suffix
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
$testRoot = Join-Path $tempBase ("qiji-word-import-test-" + [guid]::NewGuid().ToString("N"))
$fixtureRoot = Join-Path $testRoot "source"
$sandboxRoot = Join-Path $testRoot "site"

try {
  New-Item -ItemType Directory -Force -Path $fixtureRoot, $sandboxRoot | Out-Null
  foreach ($relativePath in @(
    "src\data\generatedArticles.ts",
    "src\data\reviewDraftArticles.ts",
    "src\data\generatedReview.ts",
    "src\data\publishState.json",
    "src\data\pixabayFallbackImages.json",
    "review-approvals.json",
    ".cache\article-import-cache.json"
  )) {
    Copy-TestFile $relativePath $sandboxRoot
  }
  Remove-TestIssueFromArticleModule (Join-Path $sandboxRoot "src\data\generatedArticles.ts") "generatedArticles" "generatedIssues" "202609"
  Remove-TestIssueFromArticleModule (Join-Path $sandboxRoot "src\data\reviewDraftArticles.ts") "reviewDraftArticles" "reviewDraftIssues" "202609"
  $baselineRaw = Get-Content -LiteralPath (Join-Path $sandboxRoot "src\data\generatedArticles.ts") -Raw -Encoding UTF8
  $baselineMatch = [regex]::Match($baselineRaw, 'export const generatedArticles = (?<json>[\s\S]*?) satisfies Article\[\];')
  if (-not $baselineMatch.Success) { throw "Synthetic generated article baseline is invalid." }
  $baselineArticles = @($baselineMatch.Groups["json"].Value | ConvertFrom-Json)
  if ($baselineArticles.Count -eq 0) { throw "Synthetic generated article baseline is empty." }
  if (-not $baselineArticles[0].issueId -or -not $baselineArticles[0].sourceId) {
    throw "Synthetic generated article baseline lost identity fields."
  }

  $issue408 = Join-Path $fixtureRoot "202408"
  $issue608 = Join-Path $fixtureRoot "202608"
  $issue609 = Join-Path $fixtureRoot "202609"
  New-Item -ItemType Directory -Force -Path $issue408, $issue608, $issue609 | Out-Null
  $fixtures408 = @(Get-ChildItem -LiteralPath (Join-Path $canonicalSource "202408") -File -Filter "2408-4*.docx")
  if ($fixtures408.Count -ne 2) { throw "Cannot find both duplicate-source-id 2408-4 fixtures." }
  foreach ($fixture408 in $fixtures408) {
    Copy-Item -LiteralPath $fixture408.FullName -Destination $issue408
  }
  foreach ($pattern in @("2608-1*.docx", "2608-3*.docx")) {
    $fixture608 = Get-ChildItem -LiteralPath (Join-Path $canonicalSource "202608") -File -Filter $pattern | Select-Object -First 1
    if (-not $fixture608) { throw "Cannot find the $pattern regression fixture." }
    Copy-Item -LiteralPath $fixture608.FullName -Destination $issue608
  }
  $fixture = Get-ChildItem -LiteralPath (Join-Path $canonicalSource "202609") -File -Filter "2609-2-5*.docx" | Select-Object -First 1
  if (-not $fixture) { throw "Cannot find the 2609-2-5 regression fixture." }
  $fixturePath = Join-Path $issue609 $fixture.Name
  Copy-Item -LiteralPath $fixture.FullName -Destination $fixturePath
  $authorFixture = Get-ChildItem -LiteralPath (Join-Path $canonicalSource "202609") -File -Filter "2609-2-1*.docx" | Select-Object -First 1
  if (-not $authorFixture) { throw "Cannot find the 2609-2-1 author regression fixture." }
  Copy-Item -LiteralPath $authorFixture.FullName -Destination $issue609

  $initial = Invoke-TestImport $sandboxRoot $fixtureRoot
  if (@($initial.changedFiles | Where-Object { $_.issueId -eq "202608" }).Count -ne 0) {
    throw "Unchanged 2608 content was falsely reported on cache migration."
  }
  if (@($initial.changedFiles | Where-Object { $_.issueId -eq "202408" }).Count -ne 0) {
    throw "Duplicate 2408-4 source ids were matched to the wrong published articles."
  }
  $initial609 = @($initial.changedFiles | Where-Object { $_.issueId -eq "202609" })
  if ($initial609.Count -ne 2 -or @($initial609 | Where-Object { $_.status -ne "new" }).Count -ne 0) {
    throw "A cached article missing from generated data was not reported as new."
  }
  $authorDraftRaw = Get-Content -LiteralPath (Join-Path $sandboxRoot "src\data\reviewDraftArticles.ts") -Raw -Encoding UTF8
  $authorDraftMatch = [regex]::Match($authorDraftRaw, 'export const reviewDraftArticles = (?<json>[\s\S]*?) satisfies Article\[\];')
  if (-not $authorDraftMatch.Success) { throw "Cannot read author regression output." }
  $authorDraftArticles = @($authorDraftMatch.Groups["json"].Value | ConvertFrom-Json)
  $authorArticle = $authorDraftArticles | Where-Object { $_.issueId -eq "202609" -and $_.sourceId -eq "2609-2-1" } | Select-Object -First 1
  $expectedAuthor = (-join @(0x6587, 0x7A3F, 0x4FEE, 0x6F64 | ForEach-Object { [char]$_ })) + " / " + (-join @(0x694A, 0x6E05, 0x96F2 | ForEach-Object { [char]$_ }))
  $actualAuthor = if ($authorArticle) { [string]$authorArticle.author } else { "" }
  if (
    -not $authorArticle -or
    -not $actualAuthor.Contains($expectedAuthor) -or
    $actualAuthor -match '[、，,／｜|＆&]' -or
    $actualAuthor -match '(?<! )/|/(?! )'
  ) {
    throw "Author separators were not normalized to slash: $actualAuthor"
  }
  $reviewRaw = Get-Content -LiteralPath (Join-Path $sandboxRoot "src\data\generatedReview.ts") -Raw -Encoding UTF8
  if ($reviewRaw -match '"type"\s*:\s*"possible-duplicate"') {
    throw "Distinct article titles were collapsed into one duplicate group."
  }
  Convert-TestCacheToLegacyFormat $sandboxRoot
  $legacyPoisonedHeading = Set-TestLegacyCacheHeadingToParagraph $sandboxRoot "202609"
  $unchanged = Invoke-TestImport $sandboxRoot $fixtureRoot
  if ([int]$unchanged.totalChanged -ne 0) {
    throw "Unchanged import reported changes: $($unchanged.changedFiles.fileName -join ', ')"
  }
  $legacyDraftRaw = Get-Content -LiteralPath (Join-Path $sandboxRoot "src\data\reviewDraftArticles.ts") -Raw -Encoding UTF8
  $legacyDraftMatch = [regex]::Match($legacyDraftRaw, 'export const reviewDraftArticles = (?<json>[\s\S]*?) satisfies Article\[\];')
  if (-not $legacyDraftMatch.Success) { throw "Cannot read legacy-cache regression output." }
  $legacyDraftArticles = @($legacyDraftMatch.Groups["json"].Value | ConvertFrom-Json)
  $legacyArticle = $legacyDraftArticles | Where-Object { $_.issueId -eq "202609" } | Select-Object -First 1
  $restoredLegacyBlock = $legacyArticle.contentBlocks | Where-Object { $_.text -eq $legacyPoisonedHeading } | Select-Object -First 1
  if (-not $restoredLegacyBlock -or $restoredLegacyBlock.type -ne "heading") {
    throw "An unpublished issue reused a stale legacy cache article instead of rebuilding its Word structure."
  }

  # A cache created by the current schema can still contain stale parser
  # output. The active unpublished issue must not trust that article payload.
  $currentPoisonedHeading = Set-TestLegacyCacheHeadingToParagraph $sandboxRoot "202609"
  $currentCacheRetry = Invoke-TestImport $sandboxRoot $fixtureRoot
  if ([int]$currentCacheRetry.totalChanged -ne 0) {
    throw "Reparsing an unchanged unpublished issue reported a false content change."
  }
  $currentDraftRaw = Get-Content -LiteralPath (Join-Path $sandboxRoot "src\data\reviewDraftArticles.ts") -Raw -Encoding UTF8
  $currentDraftMatch = [regex]::Match($currentDraftRaw, 'export const reviewDraftArticles = (?<json>[\s\S]*?) satisfies Article\[\];')
  if (-not $currentDraftMatch.Success) { throw "Cannot read current-cache regression output." }
  $currentDraftArticles = @($currentDraftMatch.Groups["json"].Value | ConvertFrom-Json)
  $currentArticle = $currentDraftArticles | Where-Object { $_.issueId -eq "202609" } | Select-Object -First 1
  $restoredCurrentBlock = $currentArticle.contentBlocks | Where-Object { $_.text -eq $currentPoisonedHeading } | Select-Object -First 1
  if (-not $restoredCurrentBlock -or $restoredCurrentBlock.type -ne "heading") {
    throw "An unpublished issue reused stale article output from a current-format cache."
  }

  $mutation = Set-FirstStyledParagraphStyle $fixturePath "Normal"
  $changedToNormal = Invoke-TestImport $sandboxRoot $fixtureRoot
  if ([int]$changedToNormal.totalChanged -ne 1 -or $changedToNormal.changedFiles[0].issueId -ne "202609") {
    throw "Changing a paragraph style to Normal was not reported exactly once."
  }

  [void](Set-FirstStyledParagraphStyle $fixturePath $mutation.originalStyleId)
  $changedBackToHeading = Invoke-TestImport $sandboxRoot $fixtureRoot
  if ([int]$changedBackToHeading.totalChanged -ne 1 -or $changedBackToHeading.changedFiles[0].issueId -ne "202609") {
    throw "Changing the paragraph back to its heading style was not reported exactly once."
  }

  $draftRaw = Get-Content -LiteralPath (Join-Path $sandboxRoot "src\data\reviewDraftArticles.ts") -Raw -Encoding UTF8
  $draftMatch = [regex]::Match($draftRaw, 'export const reviewDraftArticles = (?<json>[\s\S]*?) satisfies Article\[\];')
  if (-not $draftMatch.Success) { throw "Cannot read generated review draft fixture." }
  $draftArticles = $draftMatch.Groups["json"].Value | ConvertFrom-Json
  $article = $draftArticles | Where-Object { $_.issueId -eq "202609" -and $_.sourceId -eq "2609-2-5" } | Select-Object -First 1
  $block = $article.contentBlocks | Where-Object { $_.text -eq $mutation.text } | Select-Object -First 1
  if (-not $block -or $block.type -ne "heading") {
    throw "The restored Word heading style did not render as a heading."
  }

  Add-DocxPackageMetadataNoise $fixturePath
  $metadataOnly = Invoke-TestImport $sandboxRoot $fixtureRoot
  if ([int]$metadataOnly.totalChanged -ne 0) {
    throw "Package metadata noise was falsely reported as a content change."
  }

  Add-FirstStyledParagraphTextSuffix $fixturePath " IMPORT_TEST"
  $textChanged = Invoke-TestImport $sandboxRoot $fixtureRoot
  if ([int]$textChanged.totalChanged -ne 1 -or $textChanged.changedFiles[0].issueId -ne "202609") {
    throw "Visible paragraph text change was not reported exactly once."
  }

  Write-Host "PASS: unchanged documents produce zero updates."
  Write-Host "PASS: stale legacy cache is rebuilt for unpublished issues."
  Write-Host "PASS: cached articles missing from generated data are reported as new."
  Write-Host "PASS: paragraph style changes invalidate the import cache."
  Write-Host "PASS: restoring Title/Heading style renders a heading."
  Write-Host "PASS: unchanged 2608 content is not falsely reported."
  Write-Host "PASS: duplicate source ids use their published slugs without cross-matching."
  Write-Host "PASS: distinct article titles are not grouped as duplicates."
  Write-Host "PASS: package metadata noise does not produce a false update."
  Write-Host "PASS: visible paragraph text changes are reported."
  Write-Host "PASS: author separators are normalized to slash."
} finally {
  $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTestRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTestRoot)) {
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
  }
}
