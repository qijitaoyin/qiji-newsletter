param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$sourceRoot = Join-Path $Root "各期電子報"
$publicArticles = Join-Path $Root "public\assets\articles"
$generatedPath = Join-Path $Root "src\data\generatedArticles.ts"
$generatedReviewPath = Join-Path $Root "src\data\generatedReview.ts"
$reviewApprovalsPath = Join-Path $Root "review-approvals.json"
$logoPath = "/assets/qiji-logo.png"
$importCacheVersion = 7
$importCacheDir = Join-Path $Root ".cache"
$importCachePath = Join-Path $importCacheDir "article-import-cache.json"
$pixabayFallbackPath = Join-Path $Root "src\data\pixabayFallbackImages.json"
$pixabayFallbackAssetDir = Join-Path $Root "public\assets\pixabay"
$pixabayFallbackPolicy = "nature-landscape-v2"

$skipDirectoryNames = @(
  "pic", "pics", "picture", "pictures", "images", "image", "圖", "圖片", "圖片檔", "五感圖片", "傳習錄圖片", "網站",
  "draft", "drafts", "staging", "整理中", "待整理", "暫存", "暫不上架", "不上架", "未上架", "校稿中"
)

$categoryRules = @(
  @{ Pattern = "編輯小語|覺能降臨"; Category = "編輯小語"; Tags = @("編輯小語") },
  @{ Pattern = "如是我聞|疑義相與析|群組討論"; Category = "如是我聞"; Tags = @("如是我聞", "覺性修煉") },
  @{ Pattern = "體證道德經|道德經|老子"; Category = "體證道德經"; Tags = @("體證道德經", "道德經") },
  @{ Pattern = "導引按蹻|治療|骨盆"; Category = "導引按蹻"; Tags = @("導引按蹻", "身體感知") },
  @{ Pattern = "練功筆記|功夫|無極"; Category = "練功筆記"; Tags = @("練功筆記", "身體感知") },
  @{ Pattern = "導引香道|香之物語|沉香|識香|五感香道|妙觀品藏香"; Category = "導引香道"; Tags = @("導引香道") },
  @{ Pattern = "圖靈集|AI|NPC"; Category = "圖靈集"; Tags = @("圖靈集", "AI時代") },
  @{ Pattern = "心田集"; Category = "心田集"; Tags = @("心田集", "靈魂修煉") },
  @{ Pattern = "觀行錄"; Category = "觀行錄"; Tags = @("觀行錄", "覺性修煉") },
  @{ Pattern = "股海人生|貨、幣|資產負債|週期"; Category = "股海人生"; Tags = @("股海人生") },
  @{ Pattern = "導引采風|采風錄"; Category = "導引采風錄"; Tags = @("導引采風錄") },
  @{ Pattern = "同頻共振"; Category = "同頻共振"; Tags = @("同頻共振", "身體感知") },
  @{ Pattern = "身體書寫"; Category = "身體書寫"; Tags = @("身體書寫", "身體感知") },
  @{ Pattern = "山腳下的蘆葦"; Category = "山腳下的蘆葦"; Tags = @("山腳下的蘆葦", "靈魂修煉") }
)

function ConvertTo-PlainText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $value = [System.Net.WebUtility]::HtmlDecode($Text)
  $value = $value -replace "[\x00-\x08\x0B\x0C\x0E-\x1F]", ""
  $value = $value -replace "\s+", " "
  return $value.Trim()
}

function ConvertTo-PlainObject {
  param([object]$Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [System.Collections.IDictionary]) {
    $result = @{}
    foreach ($key in $Value.Keys) {
      $result[$key] = ConvertTo-PlainObject $Value[$key]
    }
    return $result
  }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $result = @{}
    foreach ($property in $Value.PSObject.Properties) {
      $result[$property.Name] = ConvertTo-PlainObject $property.Value
    }
    return $result
  }
  if ($Value -is [System.Array]) {
    return @($Value | ForEach-Object { ConvertTo-PlainObject $_ })
  }
  return $Value
}

function ConvertTo-ArrayValue {
  param([object]$Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return @($Value) }
  return @($Value)
}

function Normalize-CachedArticle {
  param([object]$Article)
  $plain = ConvertTo-PlainObject $Article
  if ($null -eq $plain -or -not ($plain -is [System.Collections.IDictionary])) { return $plain }

  foreach ($field in @("tags", "images", "contentBlocks")) {
    $plain[$field] = @(ConvertTo-ArrayValue $plain[$field])
  }

  $plain["sections"] = @(
    ConvertTo-ArrayValue $plain["sections"] | ForEach-Object {
      $section = ConvertTo-PlainObject $_
      if ($section -is [System.Collections.IDictionary]) {
        $section["paragraphs"] = @(ConvertTo-ArrayValue $section["paragraphs"])
      }
      $section
    }
  )

  return $plain
}

function Get-RelativePath {
  param([string]$Path, [string]$BasePath)
  $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $full = [System.IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $full.Substring($base.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  }
  return $full
}

function Get-FileContentHash {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  $stream = $null
  $sha = $null
  try {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($stream)
    return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
  } finally {
    if ($sha) { $sha.Dispose() }
    if ($stream) { $stream.Dispose() }
  }
}

function New-PixabayFallbackStore {
  return @{
    policy = $pixabayFallbackPolicy
    articles = @{}
    usedImageIds = @()
  }
}

function Read-PixabayFallbackStore {
  if (-not (Test-Path -LiteralPath $pixabayFallbackPath)) {
    return New-PixabayFallbackStore
  }

  try {
    $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $pixabayFallbackPath))
    if ([string]::IsNullOrWhiteSpace($raw)) {
      return New-PixabayFallbackStore
    }
    $store = ConvertTo-PlainObject ($raw | ConvertFrom-Json)
    if (-not $store.ContainsKey("policy") -or [string]$store["policy"] -ne $pixabayFallbackPolicy) {
      Write-Host "Pixabay fallback: resetting cached images for policy $pixabayFallbackPolicy."
      return New-PixabayFallbackStore
    }
    if (-not $store.ContainsKey("articles") -or $null -eq $store["articles"]) { $store["articles"] = @{} }
    if (-not $store.ContainsKey("usedImageIds") -or $null -eq $store["usedImageIds"]) { $store["usedImageIds"] = @() }
    return $store
  } catch {
    Write-Warning "Cannot read Pixabay fallback store; starting fresh. $($_.Exception.Message)"
    return New-PixabayFallbackStore
  }
}

function Save-PixabayFallbackStore {
  param([hashtable]$Store)
  $directory = Split-Path -Parent $pixabayFallbackPath
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
  }
  $json = $Store | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($pixabayFallbackPath, $json, [System.Text.UTF8Encoding]::new($false))
}

function Test-NaturalLandscapePixabayCandidate {
  param([object]$Candidate)

  $rawTags = [string]$Candidate.tags
  if ([string]::IsNullOrWhiteSpace($rawTags)) { return $false }

  $tags = @(
    $rawTags -split "," |
      ForEach-Object { $_.Trim().ToLowerInvariant() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )

  $allowedTags = @(
    "nature", "landscape", "scenery", "mountain", "mountains", "forest", "woods", "tree", "trees",
    "lake", "river", "waterfall", "ocean", "sea", "beach", "coast", "sky", "cloud", "clouds",
    "sunrise", "sunset", "valley", "meadow", "grass", "field", "flower", "flowers", "wilderness",
    "desert", "snow", "winter", "autumn", "spring", "summer", "island", "cliff", "rock", "rocks",
    "自然", "風景", "景色", "山", "森林", "樹", "湖", "河", "瀑布", "海", "海岸", "天空", "雲",
    "日出", "日落", "草原", "花", "沙漠", "雪"
  )

  $blockedTags = @(
    "people", "person", "human", "man", "woman", "child", "girl", "boy", "portrait", "face", "body",
    "city", "urban", "street", "road", "highway", "bridge", "building", "architecture", "house",
    "home", "room", "interior", "church", "temple", "tower", "castle", "car", "vehicle", "bus",
    "train", "bicycle", "bike", "boat", "ship", "airplane", "plane", "table", "chair", "bench",
    "fence", "lamp", "computer", "phone", "robot", "food", "coffee", "cup", "book", "money",
    "business", "office", "人", "人物", "人像", "城市", "街", "道路", "建築", "房子", "室內",
    "橋", "車", "船", "飛機", "桌", "椅", "電腦", "手機", "咖啡", "辦公"
  )

  foreach ($tag in $tags) {
    if ($blockedTags -contains $tag) { return $false }
  }

  foreach ($tag in $tags) {
    if ($allowedTags -contains $tag) { return $true }
  }

  return $false
}

function Get-PixabayFallbackCandidates {
  param([string]$ApiKey)
  if ([string]::IsNullOrWhiteSpace($ApiKey)) { return @() }

  $query = if ($env:PIXABAY_QUERY) { $env:PIXABAY_QUERY } else { "nature landscape mountain forest lake" }
  $encodedQuery = [System.Uri]::EscapeDataString($query)
  $maxPages = 4
  if ($env:PIXABAY_MAX_PAGES -and $env:PIXABAY_MAX_PAGES -match "^\d+$") {
    $maxPages = [Math]::Max(1, [Math]::Min(10, [int]$env:PIXABAY_MAX_PAGES))
  }
  $allHits = New-Object System.Collections.Generic.List[object]
  for ($page = 1; $page -le $maxPages; $page++) {
    try {
      $uri = "https://pixabay.com/api/?key=$ApiKey&q=$encodedQuery&category=nature&image_type=photo&orientation=horizontal&safesearch=true&per_page=200&page=$page&order=popular"
      $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 30
      $hits = @($response.hits | Where-Object {
        $_.id -and ($_.largeImageURL -or $_.webformatURL) -and (Test-NaturalLandscapePixabayCandidate $_)
      })
      if ($hits.Count -eq 0) { break }
      foreach ($hit in $hits) { $allHits.Add($hit) }
    } catch {
      Write-Warning "Cannot fetch Pixabay fallback page $page. $($_.Exception.Message)"
      break
    }
  }
  return @($allHits.ToArray())
}

function Get-PixabayAssetExtension {
  param([string]$Url)
  try {
    $path = ([System.Uri]$Url).AbsolutePath
    $extension = [System.IO.Path]::GetExtension($path)
    if ($extension -match "^\.(jpg|jpeg|png|webp)$") {
      return $extension.ToLowerInvariant()
    }
  } catch {}
  return ".jpg"
}

function Save-PixabayImageAsset {
  param([object]$Candidate)

  if (-not (Test-Path -LiteralPath $pixabayFallbackAssetDir)) {
    New-Item -ItemType Directory -Path $pixabayFallbackAssetDir -Force | Out-Null
  }

  $imageUrl = if ($Candidate.largeImageURL) { [string]$Candidate.largeImageURL } else { [string]$Candidate.webformatURL }
  $imageId = [string]$Candidate.id
  $extension = Get-PixabayAssetExtension $imageUrl
  $fileName = "pixabay-$imageId$extension"
  $destination = Join-Path $pixabayFallbackAssetDir $fileName

  if (-not (Test-Path -LiteralPath $destination)) {
    Invoke-WebRequest -Uri $imageUrl -OutFile $destination -TimeoutSec 60 | Out-Null
  }

  return "/assets/pixabay/$($fileName)?v=$imageId"
}

function Test-ValidPixabayAssetPath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  return $Path -match "^/assets/pixabay/[^/?]+\.(jpg|jpeg|png|webp)(\?v=\d+)?$"
}

function Test-NeedsPixabayFallback {
  param([object]$Article)
  $image = [string]$Article.image
  if ($image -and $image.StartsWith("/assets/pixabay/") -and -not (Test-ValidPixabayAssetPath $image)) {
    $Article.image = ""
    $Article.imageCaption = ""
    return $true
  }
  return (-not $Article.image -or $Article.image -eq $logoPath) -and @($Article.images).Count -eq 0
}

function Apply-PixabayFallbackImages {
  param([System.Collections.Generic.List[object]]$Articles)

  $apiKey = [string]$env:PIXABAY_API_KEY
  if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-Host "Pixabay fallback disabled: PIXABAY_API_KEY is not set."
    return
  }

  $missingImageArticles = @($Articles | Where-Object { Test-NeedsPixabayFallback $_ })
  if ($missingImageArticles.Count -eq 0) {
    Write-Host "Pixabay fallback: no image-less articles."
    return
  }

  $store = Read-PixabayFallbackStore
  $usedIds = New-Object System.Collections.Generic.HashSet[string]
  foreach ($entry in @($store.articles.Values)) {
    if ($entry.imageId -and $entry.path -and (Test-ValidPixabayAssetPath ([string]$entry.path))) {
      [void]$usedIds.Add([string]$entry.imageId)
    }
  }

  $candidates = @(Get-PixabayFallbackCandidates $apiKey | Sort-Object { Get-Random })
  if ($candidates.Count -eq 0) {
    Write-Warning "Pixabay fallback: no candidates returned."
    return
  }

  $applied = 0
  foreach ($article in $missingImageArticles) {
    $slug = [string]$article.slug
    $existing = $store.articles[$slug]

    if ($existing -and $existing.path -and (Test-ValidPixabayAssetPath ([string]$existing.path))) {
      $assetPath = [string]$existing.path
      $article.image = $assetPath
      $article.imageCaption = if ($existing.caption) { [string]$existing.caption } else { "圖片來源 / Pixabay" }
      $applied += 1
      continue
    } elseif ($existing -and $existing.path) {
      Write-Warning "Pixabay fallback: replacing invalid cached path for $slug."
      $store.articles.Remove($slug)
    }

    $candidate = $candidates | Where-Object { -not $usedIds.Contains([string]$_.id) } | Select-Object -First 1
    if (-not $candidate) {
      Write-Warning "Pixabay fallback: image pool exhausted before assigning $slug."
      continue
    }

    try {
      $assetPath = Save-PixabayImageAsset $candidate
      $caption = "圖片來源 / Pixabay"
      $article.image = $assetPath
      $article.imageCaption = $caption
      [void]$usedIds.Add([string]$candidate.id)
      $store.articles[$slug] = @{
        imageId = [string]$candidate.id
        path = $assetPath
        caption = $caption
        pageUrl = [string]$candidate.pageURL
        user = [string]$candidate.user
      }
      $applied += 1
    } catch {
      Write-Warning "Pixabay fallback failed for $slug. $($_.Exception.Message)"
    }
  }

  $store.usedImageIds = @($usedIds | Sort-Object)
  Save-PixabayFallbackStore $store
  Write-Host "Pixabay fallback: applied $applied image(s)."
}

function Get-FileSignature {
  param([System.IO.FileInfo]$File, [string]$BasePath, [int]$CacheVersion, [string]$ApprovalFingerprint)
  return @{
    key = Get-RelativePath $File.FullName $BasePath
    contentHash = Get-FileContentHash $File.FullName
    length = $File.Length
    cacheVersion = $CacheVersion
    approvalFingerprint = $ApprovalFingerprint
  }
}

function Test-CacheSignatureMatch {
  param([object]$Entry, [object]$Signature)
  if (-not $Entry -or -not $Entry.signature) { return $false }
  return (
    [string]$Entry.signature.key -eq [string]$Signature.key -and
    [string]$Entry.signature.contentHash -eq [string]$Signature.contentHash -and
    [string]$Entry.signature.length -eq [string]$Signature.length -and
    [string]$Entry.signature.cacheVersion -eq [string]$Signature.cacheVersion -and
    [string]$Entry.signature.approvalFingerprint -eq [string]$Signature.approvalFingerprint
  )
}

function Read-DocxParagraphs {
  param([string]$Path)
  $zip = $null
  try {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
    $entry = $zip.GetEntry("word/document.xml")
    if (-not $entry) { return @() }
    $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
    try {
      [xml]$xml = $reader.ReadToEnd()
    } finally {
      $reader.Dispose()
    }

    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $paragraphs = New-Object System.Collections.Generic.List[string]
    foreach ($p in $xml.SelectNodes("//w:body/w:p", $ns)) {
      $parts = New-Object System.Collections.Generic.List[string]
      foreach ($node in $p.SelectNodes(".//w:t|.//w:tab|.//w:br", $ns)) {
        if ($node.LocalName -eq "tab") {
          $parts.Add(" ")
        } elseif ($node.LocalName -eq "br") {
          $parts.Add(" ")
        } else {
          $parts.Add($node.InnerText)
        }
      }
      $text = ConvertTo-PlainText ($parts -join "")
      if ($text) { $paragraphs.Add($text) }
    }
    return $paragraphs.ToArray()
  } catch {
    Write-Warning "Cannot read DOCX: $Path ($($_.Exception.Message))"
    return @()
  } finally {
    if ($zip) { $zip.Dispose() }
  }
}

function Get-DocxEntryText {
  param([xml]$Xml, [System.Xml.XmlNode]$Paragraph, [System.Xml.XmlNamespaceManager]$Ns)
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($node in $Paragraph.SelectNodes(".//w:t|.//w:tab|.//w:br", $Ns)) {
    if ($node.LocalName -eq "tab") {
      $parts.Add(" ")
    } elseif ($node.LocalName -eq "br") {
      $parts.Add(" ")
    } else {
      $parts.Add($node.InnerText)
    }
  }
  return ConvertTo-PlainText ($parts -join "")
}

function Resolve-DocxMediaTarget {
  param([string]$Target)
  if ([string]::IsNullOrWhiteSpace($Target)) { return "" }
  $clean = $Target -replace "\\", "/"
  $clean = $clean.TrimStart("/")
  while ($clean.StartsWith("../")) {
    $clean = $clean.Substring(3)
  }
  if ($clean.StartsWith("word/")) { return $clean }
  return "word/$clean"
}

function Read-DocxContent {
  param(
    [System.IO.FileInfo]$File,
    [string]$IssueId,
    [string]$TargetDir,
    [ref]$ImageIndex
  )

  $zip = $null
  $paragraphs = New-Object System.Collections.Generic.List[string]
  $blocks = New-Object System.Collections.Generic.List[object]
  $images = New-Object System.Collections.Generic.List[object]
  $warnings = New-Object System.Collections.Generic.List[string]

  try {
    $stream = [System.IO.File]::Open($File.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
    $entry = $zip.GetEntry("word/document.xml")
    if (-not $entry) {
      return @{ Paragraphs = @(); Blocks = @(); Images = @(); Warnings = @("missing-document-xml") }
    }

    $relMap = @{}
    $relsEntry = $zip.GetEntry("word/_rels/document.xml.rels")
    if ($relsEntry) {
      $relReader = New-Object System.IO.StreamReader($relsEntry.Open(), [System.Text.Encoding]::UTF8)
      try {
        [xml]$relsXml = $relReader.ReadToEnd()
      } finally {
        $relReader.Dispose()
      }
      $relNs = New-Object System.Xml.XmlNamespaceManager($relsXml.NameTable)
      $relNs.AddNamespace("rel", "http://schemas.openxmlformats.org/package/2006/relationships")
      foreach ($rel in $relsXml.SelectNodes("//rel:Relationship", $relNs)) {
        $relMap[$rel.Id] = $rel.Target
      }
    }

    $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
    try {
      [xml]$xml = $reader.ReadToEnd()
    } finally {
      $reader.Dispose()
    }

    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $ns.AddNamespace("a", "http://schemas.openxmlformats.org/drawingml/2006/main")
    $ns.AddNamespace("r", "http://schemas.openxmlformats.org/officeDocument/2006/relationships")

    foreach ($p in $xml.SelectNodes("//w:body/w:p", $ns)) {
      foreach ($blip in $p.SelectNodes(".//a:blip", $ns)) {
        $rid = $blip.GetAttribute("embed", "http://schemas.openxmlformats.org/officeDocument/2006/relationships")
        if (-not $rid) { $rid = $blip.GetAttribute("link", "http://schemas.openxmlformats.org/officeDocument/2006/relationships") }
        if (-not $rid -or -not $relMap.ContainsKey($rid)) { continue }

        $mediaEntryPath = Resolve-DocxMediaTarget $relMap[$rid]
        $mediaEntry = $zip.GetEntry($mediaEntryPath)
        if (-not $mediaEntry) {
          $warnings.Add("missing-image:$mediaEntryPath")
          continue
        }

        $ext = [IO.Path]::GetExtension($mediaEntry.FullName).ToLowerInvariant()
        if ($ext -notmatch "^\.(jpg|jpeg|png|webp|gif)$") { continue }
        $name = "{0}-img-{1:D3}{2}" -f $IssueId, $ImageIndex.Value, $ext
        $destination = Join-Path $TargetDir $name
        $input = $mediaEntry.Open()
        try {
          $output = [System.IO.File]::Open($destination, [System.IO.FileMode]::Create)
          try {
            $input.CopyTo($output)
          } finally {
            $output.Dispose()
          }
        } finally {
          $input.Dispose()
        }

        $image = @{
          src = Get-ArticleAssetPath $IssueId $name $destination
          caption = ""
        }
        $images.Add($image)
        $blocks.Add(@{
          type = "image"
          src = $image.src
          caption = ""
        })
        $ImageIndex.Value = $ImageIndex.Value + 1
      }

      $text = Get-DocxEntryText $xml $p $ns
      if ($text) {
        $paragraphs.Add($text)
        $blocks.Add(@{ type = "paragraph"; text = $text })
      }
    }
  } catch {
    Write-Warning "Cannot read DOCX content: $($File.FullName) ($($_.Exception.Message))"
    $warnings.Add("read-error:$($_.Exception.Message)")
  } finally {
    if ($zip) { $zip.Dispose() }
  }

  return @{
    Paragraphs = $paragraphs.ToArray()
    Blocks = $blocks.ToArray()
    Images = $images.ToArray()
    Warnings = $warnings.ToArray()
  }
}

function Get-IssueNumber {
  param([string]$IssueId)
  $year = [int]$IssueId.Substring(0, 4)
  $month = [int]$IssueId.Substring(4, 2)
  $monthsFromLatest = ((2026 - $year) * 12) + (5 - $month)
  return 243 - $monthsFromLatest
}

function Get-CleanTitle {
  param([string]$Stem)
  $title = $Stem
  $title = $title -replace "^\d{6}[_\-\s\.]*", ""
  $title = $title -replace "^\d{4}[_\-\s\.]*", ""
  $title = $title -replace "^\d{2}[_\-\s\.]*", ""
  $title = $title -replace "^[\d\-_\.]+\s*", ""
  $title = $title -replace "_", " "
  $title = $title -replace "\s+", " "
  $title = $title.Trim(" -_　.")
  if (-not $title) { return $Stem }
  return $title
}

function Get-SourceId {
  param([string]$IssueId, [string]$Stem)
  if ($Stem -match "^(\d{4,6}(?:[_\-]\d+){0,3})") {
    return ($Matches[1] -replace "_", "-")
  }
  return "$IssueId-" + (($Stem.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-"))
}

function Get-Slug {
  param([string]$IssueId, [string]$SourceId, [string]$Title)
  $ascii = ($SourceId.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-")
  if (-not $ascii) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Title)
    $hash = [BitConverter]::ToString((New-Object System.Security.Cryptography.SHA1Managed).ComputeHash($bytes)).Replace("-", "").Substring(0, 10).ToLowerInvariant()
    $ascii = $hash
  }
  if (-not $ascii.StartsWith($IssueId)) { $ascii = "$IssueId-$ascii" }
  return $ascii
}

function Get-CategoryInfo {
  param([string]$Title)
  foreach ($rule in $categoryRules) {
    if ($Title -match $rule.Pattern) {
      return @{ Category = $rule.Category; Tags = $rule.Tags }
    }
  }
  return @{ Category = "專欄文章"; Tags = @("專欄文章") }
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
  $baseCategoryInfo = Get-CategoryInfo $seriesTitle
  $category = if ($baseCategoryInfo.Category -eq $seriesTitle) {
    $seriesTitle
  } else {
    "$($baseCategoryInfo.Category)/$seriesTitle"
  }
  return @{
    SeriesTitle = $seriesTitle
    Part = $marker.Value
    Category = $category
    Tags = @(($baseCategoryInfo.Tags + $seriesTitle) | Select-Object -Unique)
  }
}

function Normalize-ArticleText {
  param([string]$Text)
  if (-not $Text) { return "" }
  $normalized = $Text -replace "\s+", ""
  $normalized = $normalized.Trim("【】「」『』《》〈〉（）()[]［］：:，,。．.、；;！!?？-－—_　 ")
  return $normalized
}

function Test-HeaderAuthorLine {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $value = $Text.Trim()
  if ($value.Length -gt 40) { return $false }
  if ($value -match "^【") { return $false }
  if ($value -match "[。！？；：]$") { return $false }
  return $true
}

function Test-LegacyCategoryLine {
  param([string]$Text, [string]$Category)
  if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Category)) { return $false }
  $value = $Text.Trim()
  $key = (Normalize-ArticleText $value) -replace "[^\p{L}\p{N}]", ""
  $categoryKey = (Normalize-ArticleText $Category) -replace "[^\p{L}\p{N}]", ""
  if (-not $key -or -not $categoryKey) { return $false }
  if ($key -eq $categoryKey -or $key.Contains($categoryKey)) { return $true }
  if ($Category -eq "觀行錄" -and $key -match "觀行錄|觀.*行.*錄") { return $true }
  return $false
}

function Test-LegacyAuthorLine {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $value = $Text.Trim()
  if ($value.Length -gt 64) { return $false }
  if ($value -match "[。！？；]$") { return $false }
  if ($value -match "^(文|整理|撰文|作者|編輯|口述|彙整)[／/：:]") { return $true }
  if ($value -match "莫仁維|張尊堡|Richard\s+Moh|Bob\s+Chang") { return $true }
  if ($value -match "^[\u4e00-\u9fff](\s+[\u4e00-\u9fff]){1,4}$") { return $true }
  if ($value -match "^[\u4e00-\u9fff]{2,4}([、，,／/\s和與][\u4e00-\u9fff]{2,4}){0,4}$") { return $true }
  return $false
}

function Test-LegacyKnownAuthorLine {
  param([string]$Text)
  if (-not (Test-LegacyAuthorLine $Text)) { return $false }
  $value = $Text.Trim()
  if ($value -match "^(文|整理|撰文|作者|編輯|口述|彙整)[／/：:]") { return $true }
  if ($value -match "莫仁維|張尊堡|Richard\s+Moh|Bob\s+Chang") { return $true }
  if ($value -match "^[\u4e00-\u9fff]{2,4}([、，,／/\s和與][\u4e00-\u9fff]{2,4}){1,4}$") { return $true }
  return $false
}

function Convert-LegacyAuthorLine {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $value = $Text.Trim()
  if ($value -match "^[\u4e00-\u9fff](\s+[\u4e00-\u9fff]){1,4}$") {
    return ($value -replace "\s+", "")
  }
  $nameMatches = [regex]::Matches($value, "[\u4e00-\u9fff]{2,4}") |
    ForEach-Object { $_.Value } |
    Where-Object { $_ -notin @("翻譯", "作者", "撰文", "整理", "編輯", "口述", "彙整") }
  if ($value -match "Richard\s+Moh|Bob\s+Chang|Translated" -and $nameMatches.Count -gt 0) {
    return (($nameMatches | Select-Object -Unique) -join "、")
  }
  if ($value -match "^[\u4e00-\u9fff]{2,4}([、，,／/\s和與][\u4e00-\u9fff]{2,4}){1,4}$" -and $nameMatches.Count -gt 0) {
    return (($nameMatches | Select-Object -Unique) -join "、")
  }
  return $value
}

function Parse-LegacyHeader {
  param([string[]]$Paragraphs, [string]$InitialTitle, [string]$Category)
  $result = @{
    Title = $InitialTitle
    Author = ""
    BodyParagraphs = $Paragraphs
    HasHeader = $false
    Category = ""
    Tags = @()
  }
  if (-not $Paragraphs -or $Paragraphs.Count -eq 0) { return $result }

  $seriesInfo = Get-SeriesHeaderInfo $Paragraphs[0]
  if ($seriesInfo -and $Paragraphs.Count -ge 3) {
    $subtitle = $Paragraphs[1].Trim("【】「」 ")
    $authorCandidate = $Paragraphs[2]
    if ($subtitle -and (Test-LegacyAuthorLine $authorCandidate)) {
      $result.Title = $subtitle
      $result.Author = Convert-LegacyAuthorLine $authorCandidate
      $result.BodyParagraphs = $Paragraphs | Select-Object -Skip 3
      $result.HasHeader = $true
      $result.Category = $seriesInfo.Category
      $result.Tags = $seriesInfo.Tags
      return $result
    }
  }

  if ($Paragraphs.Count -ge 2 -and $Paragraphs[0] -match "電子報|第\d+期|·") {
    $candidateTitle = $Paragraphs[1].Trim("【】「」 ")
    if ($candidateTitle.Length -gt 0 -and $candidateTitle.Length -le 64) {
      $result.Title = $candidateTitle
      $result.HasHeader = $true
      if ($Paragraphs.Count -ge 3 -and (Test-LegacyAuthorLine $Paragraphs[2])) {
        $result.Author = Convert-LegacyAuthorLine $Paragraphs[2]
        $result.BodyParagraphs = $Paragraphs | Select-Object -Skip 3
      } else {
        $result.BodyParagraphs = $Paragraphs | Select-Object -Skip 2
      }
    }
    return $result
  }

  $firstLine = $Paragraphs[0].Trim("【】「」 ")
  if (Test-LegacyCategoryLine $firstLine $Category) {
    $result.HasHeader = $true
    if (
      $Paragraphs.Count -ge 4 -and
      $Paragraphs[1] -match "[A-Za-z]" -and
      $Paragraphs[2].Length -le 32 -and
      $Paragraphs[2] -match "[\u4e00-\u9fff]" -and
      $Paragraphs[2] -notmatch "莫仁維|張尊堡|Richard\s+Moh|Bob\s+Chang" -and
      (Test-LegacyKnownAuthorLine $Paragraphs[3])
    ) {
      $result.Title = $Paragraphs[2].Trim("【】「」 ")
      $authorParts = New-Object System.Collections.Generic.List[string]
      $authorParts.Add((Convert-LegacyAuthorLine $Paragraphs[3]))
      $skip = 4
      if ($Paragraphs.Count -ge 5 -and (Test-LegacyKnownAuthorLine $Paragraphs[4])) {
        $authorParts.Add((Convert-LegacyAuthorLine $Paragraphs[4]))
        $skip = 5
      }
      $result.Author = (($authorParts | Where-Object { $_ } | Select-Object -Unique) -join "、")
      $result.BodyParagraphs = $Paragraphs | Select-Object -Skip $skip
      return $result
    }
    if ($Paragraphs.Count -ge 3 -and (Test-LegacyKnownAuthorLine $Paragraphs[2])) {
      $result.Title = $Paragraphs[1].Trim("【】「」 ")
      $authorParts = New-Object System.Collections.Generic.List[string]
      $authorParts.Add((Convert-LegacyAuthorLine $Paragraphs[2]))
      if ($Paragraphs.Count -ge 4 -and (Test-LegacyKnownAuthorLine $Paragraphs[3])) {
        $authorParts.Add((Convert-LegacyAuthorLine $Paragraphs[3]))
        $result.BodyParagraphs = $Paragraphs | Select-Object -Skip 4
      } else {
        $result.BodyParagraphs = $Paragraphs | Select-Object -Skip 3
      }
      $result.Author = (($authorParts | Where-Object { $_ } | Select-Object -Unique) -join "、")
      return $result
    }
    if (
      $Paragraphs.Count -ge 4 -and
      $Paragraphs[1].Length -le 64 -and
      $Paragraphs[2].Length -le 64 -and
      $Paragraphs[1] -match "[\u4e00-\u9fff]" -and
      $Paragraphs[2] -match "[\u4e00-\u9fff]" -and
      (Test-LegacyAuthorLine $Paragraphs[3])
    ) {
      $titleParts = @(
        $Paragraphs[1].Trim("【】「」 "),
        $Paragraphs[2].Trim("【】「」 ")
      ) | Where-Object { $_ }
      $result.Title = ($titleParts -join "")
      $result.Author = Convert-LegacyAuthorLine $Paragraphs[3]
      $result.BodyParagraphs = $Paragraphs | Select-Object -Skip 4
      return $result
    }
    if (
      $Paragraphs.Count -ge 3 -and
      $Paragraphs[1] -match "[A-Za-z]" -and
      $Paragraphs[2].Length -le 32 -and
      $Paragraphs[2] -match "[\u4e00-\u9fff]"
    ) {
      $result.Title = $Paragraphs[2].Trim("【】「」 ")
      $authorParts = New-Object System.Collections.Generic.List[string]
      $skip = 3
      if ($Paragraphs.Count -ge 4 -and (Test-LegacyKnownAuthorLine $Paragraphs[3])) {
        $authorParts.Add((Convert-LegacyAuthorLine $Paragraphs[3]))
        $skip = 4
      }
      if ($Paragraphs.Count -ge 5 -and (Test-LegacyKnownAuthorLine $Paragraphs[4])) {
        $authorParts.Add((Convert-LegacyAuthorLine $Paragraphs[4]))
        $skip = 5
      }
      $result.Author = (($authorParts | Where-Object { $_ } | Select-Object -Unique) -join "、")
      $result.BodyParagraphs = $Paragraphs | Select-Object -Skip $skip
      return $result
    }
    if ($Paragraphs.Count -ge 3 -and $Paragraphs[2].Length -le 32 -and $Paragraphs[2] -match "[\u4e00-\u9fff]") {
      $result.Title = $Paragraphs[2].Trim("【】「」 ")
      $result.BodyParagraphs = $Paragraphs | Select-Object -Skip 3
      return $result
    }
    if ($Paragraphs.Count -ge 2) {
      $result.Title = $Paragraphs[1].Trim("【】「」 ")
      $result.BodyParagraphs = $Paragraphs | Select-Object -Skip 2
    }
    return $result
  }

  if ($Paragraphs.Count -ge 3 -and (Test-LegacyAuthorLine $Paragraphs[2])) {
    $result.HasHeader = $true
    if ($Paragraphs[1] -match "[\u4e00-\u9fff]" -and $Paragraphs[0] -match "[A-Za-z]") {
      $result.Title = $Paragraphs[1].Trim("【】「」 ")
    } else {
      $result.Title = $Paragraphs[0].Trim("【】「」 ")
    }
    $authorParts = New-Object System.Collections.Generic.List[string]
    $authorParts.Add((Convert-LegacyAuthorLine $Paragraphs[2]))
    if ($Paragraphs.Count -ge 4 -and (Test-LegacyAuthorLine $Paragraphs[3])) {
      $authorParts.Add((Convert-LegacyAuthorLine $Paragraphs[3]))
      $result.BodyParagraphs = $Paragraphs | Select-Object -Skip 4
    } else {
      $result.BodyParagraphs = $Paragraphs | Select-Object -Skip 3
    }
    $result.Author = (($authorParts | Where-Object { $_ } | Select-Object -Unique) -join "、")
    return $result
  }

  return $result
}

function Split-Sections {
  param([string[]]$Paragraphs)
  $sections = New-Object System.Collections.Generic.List[object]
  $current = @{ paragraphs = New-Object System.Collections.Generic.List[string] }
  for ($i = 0; $i -lt $Paragraphs.Count; $i++) {
    $text = $Paragraphs[$i]
    $next = if ($i + 1 -lt $Paragraphs.Count) { $Paragraphs[$i + 1] } else { "" }
    $looksHeading = ($text.Length -le 24 -and $next.Length -ge 30 -and $text -notmatch "[。！？；：]$")
    if ($looksHeading -and $current.paragraphs.Count -gt 0) {
      $sections.Add(@{ paragraphs = $current.paragraphs.ToArray() })
      $current = @{ heading = $text; paragraphs = New-Object System.Collections.Generic.List[string] }
    } else {
      $current.paragraphs.Add($text)
    }
  }
  if ($current.paragraphs.Count -gt 0 -or $current.ContainsKey("heading")) {
    $sections.Add(@{ heading = $current.heading; paragraphs = $current.paragraphs.ToArray() })
  }
  return $sections.ToArray()
}

function Get-TemplateFieldValue {
  param([string[]]$Lines, [string]$Name)
  $pattern = "^" + [regex]::Escape($Name) + "\s*[：:]\s*(.+?)\s*$"
  foreach ($line in $Lines) {
    if ($line -match $pattern) {
      $value = $Matches[1].Trim()
      $value = ($value -replace "\s+(文章分類|分類|類別|欄目|單元|文章標題|標題|題名|作者|撰文|文稿彙整|文稿整理|整理|編輯|口述|文|日期|期數|圖片來源|照片來源|開頭圖片來源)\s*[：:].*$", "").Trim()
      return $value
    }
  }
  return ""
}

function Get-TemplateFieldValueAny {
  param([string[]]$Lines, [string[]]$Names)
  foreach ($name in $Names) {
    $value = Get-TemplateFieldValue $Lines $name
    if ($value) { return $value }
  }
  return ""
}

function Test-TemplateBodyMarker {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $value = $Text.Trim()
  return ($value -match "^【?\s*(正文開始|正文|內文開始|內文)\s*】?\s*[：:]?\s*$")
}

function Test-TemplateControlLine {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $value = $Text.Trim()
  if (Test-TemplateBodyMarker $value) { return $true }
  if ($value -match "^(文章分類|分類|類別|欄目|單元|文章標題|標題|題名|作者|撰文|文稿彙整|文稿整理|整理|編輯|口述|文|日期|期數|圖片來源|照片來源|開頭圖片來源)\s*[：:]") {
    return $true
  }
  if ($value -match "^【\s*(氣機導引電子報文章資料|氣機導引電子報範本|文章資料|正文開始|正文|內文開始|內文)\s*】$") {
    return $true
  }
  return $false
}

function Get-TemplateBodyIndex {
  param([string[]]$Paragraphs)
  $strictIndex = [Array]::IndexOf($Paragraphs, "【正文開始】")
  if ($strictIndex -ge 0) { return $strictIndex }
  for ($i = 0; $i -lt [Math]::Min($Paragraphs.Count, 40); $i++) {
    if (Test-TemplateBodyMarker $Paragraphs[$i]) { return $i }
  }
  return -1
}

function Get-TemplateMetaIndex {
  param([string[]]$Paragraphs)
  $knownMarkers = @("【氣機導引電子報文章資料】", "【氣機導引電子報範本】", "【文章資料】")
  foreach ($marker in $knownMarkers) {
    $index = [Array]::IndexOf($Paragraphs, $marker)
    if ($index -ge 0) { return $index }
  }
  return -1
}

function Get-LooseCategoryValue {
  param([string[]]$Lines)
  $category = Get-TemplateFieldValueAny $Lines @("文章分類", "分類", "類別", "欄目", "單元")
  if ($category) { return $category }
  foreach ($line in $Lines) {
    $value = $line.Trim()
    if ($value -match "^【\s*(.+?)\s*】$") {
      $candidate = $Matches[1].Trim()
      if ($candidate -and $candidate -notmatch "氣機導引電子報|文章資料|範本|正文|內文") {
        return $candidate
      }
    }
  }
  return ""
}

function Parse-ArticleTemplate {
  param([string[]]$Paragraphs, [string]$IssueId)
  $metaIndex = Get-TemplateMetaIndex $Paragraphs
  $bodyIndex = Get-TemplateBodyIndex $Paragraphs
  $hasTemplate = $metaIndex -ge 0 -or $bodyIndex -ge 0

  if ($metaIndex -lt 0) {
    $looseBodyIndex = $bodyIndex
    $looseMetaLines = if ($looseBodyIndex -gt 0) {
      $Paragraphs | Select-Object -First $looseBodyIndex
    } else {
      $Paragraphs | Select-Object -First ([Math]::Min($Paragraphs.Count, 8))
    }
    $looseCategory = Get-LooseCategoryValue $looseMetaLines
    $looseTitle = Get-TemplateFieldValueAny $looseMetaLines @("文章標題", "標題", "題名")
    $looseAuthor = Get-TemplateFieldValueAny $looseMetaLines @("作者", "撰文", "文稿彙整", "文稿整理", "整理", "編輯", "口述", "文")
    $looseDate = Get-TemplateFieldValue $looseMetaLines "日期"
    $looseImageSource = Get-TemplateFieldValueAny $looseMetaLines @("圖片來源", "照片來源", "開頭圖片來源")
    if ($looseCategory -and $looseTitle -and $looseAuthor -and $looseBodyIndex -ge 0) {
      if (-not $looseDate) {
        $looseDate = "{0}.{1}.10" -f $IssueId.Substring(0, 4), $IssueId.Substring(4, 2)
      }
      return @{
        HasTemplate = $true
        IsValid = $true
        IsLooseTemplate = $true
        Errors = @()
        BodyStart = $looseBodyIndex + 1
        BodyMarker = $Paragraphs[$looseBodyIndex]
        Category = $looseCategory
        Title = $looseTitle
        Author = $looseAuthor
        Date = $looseDate
        ImageSource = $looseImageSource
      }
    }
    if ($looseBodyIndex -ge 0) {
      $looseErrors = New-Object System.Collections.Generic.List[string]
      if (-not $looseCategory) { $looseErrors.Add("缺少文章分類") }
      if (-not $looseTitle) { $looseErrors.Add("缺少文章標題") }
      if (-not $looseAuthor) { $looseErrors.Add("缺少作者") }
      if (-not $looseDate) {
        $looseDate = "{0}.{1}.10" -f $IssueId.Substring(0, 4), $IssueId.Substring(4, 2)
      }
      return @{
        HasTemplate = $true
        IsValid = $false
        IsLooseTemplate = $true
        Errors = $looseErrors.ToArray()
        BodyStart = $looseBodyIndex + 1
        BodyMarker = $Paragraphs[$looseBodyIndex]
        Category = $looseCategory
        Title = $looseTitle
        Author = $looseAuthor
        Date = $looseDate
        ImageSource = $looseImageSource
      }
    }
    return @{ HasTemplate = $false; IsValid = $false; Errors = @(); BodyStart = 0; IsLooseTemplate = $false; BodyMarker = "" }
  }

  $errors = New-Object System.Collections.Generic.List[string]
  if ($metaIndex -lt 0) { $errors.Add("缺少【氣機導引電子報文章資料】") }
  if ($bodyIndex -lt 0) { $errors.Add("缺少【正文開始】") }
  if ($metaIndex -ge 0 -and $bodyIndex -ge 0 -and $bodyIndex -le $metaIndex) {
    $errors.Add("【正文開始】必須放在文章資料欄位之後")
  }

  $metaLines = @()
  if ($metaIndex -ge 0 -and $bodyIndex -gt $metaIndex) {
    $metaLines = $Paragraphs | Select-Object -Skip ($metaIndex + 1) -First ($bodyIndex - $metaIndex - 1)
  }

  $category = Get-LooseCategoryValue $metaLines
  $title = Get-TemplateFieldValueAny $metaLines @("文章標題", "標題", "題名")
  $author = Get-TemplateFieldValueAny $metaLines @("作者", "撰文", "文稿彙整", "文稿整理", "整理", "編輯", "口述", "文")
  $date = Get-TemplateFieldValue $metaLines "日期"
  $imageSource = Get-TemplateFieldValueAny $metaLines @("圖片來源", "照片來源", "開頭圖片來源")

  if (-not $category) { $errors.Add("缺少文章分類") }
  if (-not $title) { $errors.Add("缺少文章標題") }
  if (-not $author) { $errors.Add("缺少作者") }
  if (-not $date) {
    $date = "{0}.{1}.10" -f $IssueId.Substring(0, 4), $IssueId.Substring(4, 2)
  }

  return @{
    HasTemplate = $true
    IsLooseTemplate = $false
    IsValid = ($errors.Count -eq 0)
    Errors = $errors.ToArray()
    BodyStart = if ($bodyIndex -ge 0) { $bodyIndex + 1 } else { $Paragraphs.Count }
    BodyMarker = if ($bodyIndex -ge 0) { $Paragraphs[$bodyIndex] } else { "【正文開始】" }
    Category = $category
    Title = $title
    Author = $author
    Date = $date
    ImageSource = $imageSource
  }
}

function Select-BodyBlocks {
  param([object[]]$Blocks, [string[]]$BodyParagraphs)
  $bodyQueue = New-Object System.Collections.Queue
  foreach ($p in $BodyParagraphs) { $bodyQueue.Enqueue($p) }

  $selected = New-Object System.Collections.Generic.List[object]
  $started = $false
  foreach ($block in $Blocks) {
    if ($block.type -eq "paragraph") {
      if (-not $started) {
        if ($bodyQueue.Count -gt 0 -and $block.text -eq $bodyQueue.Peek()) {
          $started = $true
        } else {
          continue
        }
      }
      if ($bodyQueue.Count -gt 0 -and $block.text -eq $bodyQueue.Peek()) {
        [void]$bodyQueue.Dequeue()
        $selected.Add($block)
      }
    } elseif ($started) {
      $selected.Add($block)
    }
  }
  return $selected.ToArray()
}

function Select-BlocksAfterText {
  param([object[]]$Blocks, [string]$Marker)
  $selected = New-Object System.Collections.Generic.List[object]
  $started = $false
  foreach ($block in $Blocks) {
    if (-not $started) {
      if ($block.type -eq "paragraph" -and $block.text -eq $Marker) {
        $started = $true
      }
      continue
    }
    $selected.Add($block)
  }
  return $selected.ToArray()
}

function Resolve-ImageCaptions {
  param([object[]]$Blocks, [System.Collections.Generic.List[string]]$Warnings)
  $resolved = New-Object System.Collections.Generic.List[object]
  $lastImage = $null
  foreach ($block in $Blocks) {
    if ($block.type -eq "image") {
      $resolved.Add($block)
      $lastImage = $block
      continue
    }
    if ($block.type -eq "paragraph" -and $block.text -match "^圖片標題[：:]\s*(.+?)\s*$") {
      if ($lastImage) {
        $lastImage.caption = $Matches[1].Trim()
      } else {
        $Warnings.Add("圖片標題沒有對應前一張圖片：$($block.text)")
      }
      continue
    }
    if ($block.type -eq "paragraph" -and $block.text -match "^圖片標題[：:]\s*$") {
      if (-not $lastImage) {
        $Warnings.Add("空白圖片標題沒有對應前一張圖片")
      }
      continue
    }
    $resolved.Add($block)
  }
  foreach ($block in $resolved) {
    if ($block.type -eq "image" -and -not $block.caption) {
      $Warnings.Add("圖片無標題：$($block.src)")
    }
  }
  return $resolved.ToArray()
}

function Get-ImageSourceCaption {
  param([string[]]$Paragraphs)
  foreach ($paragraph in $Paragraphs) {
    if ($paragraph -match "^圖片來源\s*[／/：:]\s*(.+?)\s*$") {
      return "圖片來源 / $($Matches[1].Trim())"
    }
  }
  return ""
}

function Get-ReviewCorrectionValue {
  param([object]$Correction, [string]$Name)
  if (-not $Correction -or -not $Correction.corrections) { return "" }
  $property = $Correction.corrections.PSObject.Properties[$Name]
  if (-not $property) { return "" }
  return ([string]$property.Value).Trim()
}

function Test-BodyParagraphLike {
  param([string]$Text)
  if (-not $Text) { return $false }
  $value = $Text.Trim()
  if ($value.Length -ge 24) { return $true }
  return ($value -match "[，。！？；：]")
}

function Remove-HeaderLikeBlocks {
  param(
    [object[]]$Blocks,
    [string]$Title,
    [string]$Author,
    [string]$Category
  )
  $titleKey = Normalize-ArticleText $Title
  $authorKey = Normalize-ArticleText (Convert-LegacyAuthorLine $Author)
  $cleaned = New-Object System.Collections.Generic.List[object]
  foreach ($block in $Blocks) {
    if ($block.type -ne "paragraph") {
      $cleaned.Add($block)
      continue
    }
    $text = ([string]$block.text).Trim()
    $paragraphKey = Normalize-ArticleText $text
    $paragraphAuthorKey = Normalize-ArticleText (Convert-LegacyAuthorLine $text)
    if (Test-TemplateControlLine $text) { continue }
    if ($text -match "^圖片來源") { continue }
    if ($text -match "^\d{4}[./-]\d{1,2}[./-]\d{1,2}$") { continue }
    if ($titleKey -and $paragraphKey -eq $titleKey) { continue }
    if ($authorKey -and $text.Length -le 64 -and ($paragraphKey -eq $authorKey -or $paragraphAuthorKey -eq $authorKey)) { continue }
    if (Test-LegacyCategoryLine $text $Category) { continue }
    $cleaned.Add($block)
  }
  return $cleaned.ToArray()
}

function Convert-BlocksToDisplayBlocks {
  param([object[]]$Blocks)
  $display = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $Blocks.Count; $i++) {
    $block = $Blocks[$i]
    if ($block.type -ne "paragraph") {
      $display.Add($block)
      continue
    }

    $nextText = ""
    for ($j = $i + 1; $j -lt $Blocks.Count; $j++) {
      if ($Blocks[$j].type -eq "paragraph") {
        $nextText = $Blocks[$j].text
        break
      }
    }
    $looksHeading = ($block.text.Length -le 24 -and $nextText.Length -ge 30 -and $block.text -notmatch "[。！？；：]$")
    if ($looksHeading) {
      $display.Add(@{ type = "heading"; text = $block.text })
    } else {
      $display.Add($block)
    }
  }
  return $display.ToArray()
}

function Get-Excerpt {
  param([string[]]$Paragraphs)
  foreach ($p in $Paragraphs) {
    if ($p.Length -ge 36) {
      if ($p.Length -gt 96) { return $p.Substring(0, 96) + "…" }
      return $p
    }
  }
  if ($Paragraphs.Count -gt 0) { return $Paragraphs[0] }
  return ""
}

function Test-InNestedIssuePath {
  param([string]$Path, [System.IO.DirectoryInfo]$IssueDir)
  $relative = $Path.Substring($IssueDir.FullName.Length).TrimStart("\", "/")
  if (-not $relative) { return $false }
  foreach ($part in ($relative -split "[\\/]")) {
    if ($part -match "^(20\d{4})" -and $Matches[1] -ne ([regex]::Match($IssueDir.Name, "20\d{4}")).Value) {
      return $true
    }
  }
  return $false
}

function Test-UsableImageFile {
  param([System.IO.FileInfo]$File)
  if ($File.Name.StartsWith("._") -or $File.Name.StartsWith("~$")) { return $false }
  if ($File.Length -le 0) { return $false }

  $stream = $null
  try {
    $stream = [System.IO.File]::OpenRead($File.FullName)
    $buffer = New-Object byte[] 12
    $read = $stream.Read($buffer, 0, $buffer.Length)
    if ($read -lt 4) { return $false }

    $ext = $File.Extension.ToLowerInvariant()
    if ($ext -in @(".jpg", ".jpeg")) {
      return ($buffer[0] -eq 0xFF -and $buffer[1] -eq 0xD8)
    }
    if ($ext -eq ".png") {
      return ($buffer[0] -eq 0x89 -and $buffer[1] -eq 0x50 -and $buffer[2] -eq 0x4E -and $buffer[3] -eq 0x47)
    }
    if ($ext -eq ".gif") {
      $signature = [System.Text.Encoding]::ASCII.GetString($buffer, 0, [Math]::Min(3, $read))
      return ($signature -eq "GIF")
    }
    if ($ext -eq ".webp") {
      if ($read -lt 12) { return $false }
      $riff = [System.Text.Encoding]::ASCII.GetString($buffer, 0, 4)
      $webp = [System.Text.Encoding]::ASCII.GetString($buffer, 8, 4)
      return ($riff -eq "RIFF" -and $webp -eq "WEBP")
    }
    return $true
  } catch {
    return $false
  } finally {
    if ($stream) { $stream.Dispose() }
  }
}

function Get-ArticleAssetPath {
  param([string]$IssueId, [string]$FileName, [string]$FilePath)
  $version = (Get-Item -LiteralPath $FilePath).Length
  return "/assets/articles/${IssueId}/${FileName}?v=${version}"
}

function Test-FileCopyNeeded {
  param([System.IO.FileInfo]$Source, [string]$Destination)
  if (-not (Test-Path -LiteralPath $Destination)) { return $true }
  $targetItem = Get-Item -LiteralPath $Destination
  if ($targetItem.Length -ne $Source.Length) { return $true }
  if ($targetItem.LastWriteTimeUtc -lt $Source.LastWriteTimeUtc) { return $true }
  return $false
}

function Copy-IssueImages {
  param([string]$IssueId, [System.IO.DirectoryInfo]$IssueDir)
  $target = Join-Path $publicArticles $IssueId
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  $images = Get-ChildItem -Path $IssueDir.FullName -Recurse -File |
    Where-Object { $_.Extension -match "^\.(jpg|jpeg|png|webp|gif)$" } |
    Where-Object { Test-UsableImageFile $_ } |
    Where-Object { -not (Test-InNestedIssuePath $_.FullName $IssueDir) } |
    Sort-Object FullName
  $copied = New-Object System.Collections.Generic.List[object]
  $index = 1
  foreach ($image in $images) {
    $ext = $image.Extension.ToLowerInvariant()
    $name = "{0}-img-{1:D3}{2}" -f $IssueId, $index, $ext
    $destination = Join-Path $target $name
    if (Test-FileCopyNeeded $image $destination) {
      Copy-Item -LiteralPath $image.FullName -Destination $destination -Force
      (Get-Item -LiteralPath $destination).LastWriteTimeUtc = $image.LastWriteTimeUtc
    }
    $copied.Add(@{
      sourceName = [IO.Path]::GetFileNameWithoutExtension($image.Name)
      path = Get-ArticleAssetPath $IssueId $name $destination
    })
    $index++
  }
  return $copied.ToArray()
}

function Select-ArticleImage {
  param([object[]]$Images, [string]$SourceId, [string]$Title, [int]$Index)
  if (-not $Images -or $Images.Count -eq 0) { return "" }
  $needle = ($SourceId -replace "^20\d{2}", "") -replace "[^\d]", ""
  if ($needle) {
    $match = $Images | Where-Object { $_.sourceName -replace "[^\d]", "" -like "*$needle*" } | Select-Object -First 1
    if ($match) { return $match.path }
  }
  $titleMatch = $Images | Where-Object { $Title -and $_.sourceName -and ($Title.Contains($_.sourceName) -or $_.sourceName.Contains($Title)) } | Select-Object -First 1
  if ($titleMatch) { return $titleMatch.path }
  return ""
}

function Should-SkipDoc {
  param([System.IO.FileInfo]$File)
  if ($File.Length -le 0) { return $true }
  if ($File.Name.StartsWith("~$")) { return $true }
  if ($File.Name.StartsWith("._")) { return $true }
  $stem = [IO.Path]::GetFileNameWithoutExtension($File.Name)
  if ($stem -match "(^|[_\-\s])0{1,2}[_\-\s]*目錄|目錄$|徵稿啟事") { return $true }
  $dirNames = $File.DirectoryName.Split([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  foreach ($name in $dirNames) {
    if ($skipDirectoryNames -contains $name.ToLowerInvariant()) { return $true }
  }
  return $false
}

function Test-SkippedDirectoryPath {
  param([System.IO.DirectoryInfo]$Directory)
  $dirNames = $Directory.FullName.Split([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  foreach ($name in $dirNames) {
    if ($skipDirectoryNames -contains $name.ToLowerInvariant()) { return $true }
  }
  return $false
}

function Test-NestedIssueDoc {
  param([System.IO.FileInfo]$File, [System.IO.DirectoryInfo]$IssueDir)
  $relativeDir = $File.DirectoryName.Substring($IssueDir.FullName.Length).TrimStart("\", "/")
  if (-not $relativeDir) { return $false }
  foreach ($part in ($relativeDir -split "[\\/]")) {
    if ($part -match "^(20\d{4})" -and $Matches[1] -ne ([regex]::Match($IssueDir.Name, "20\d{4}")).Value) {
      return $true
    }
  }
  return $false
}

function Test-InGmailFolder {
  param([System.IO.FileInfo]$File, [System.IO.DirectoryInfo]$IssueDir)
  $relativeDir = $File.DirectoryName.Substring($IssueDir.FullName.Length).TrimStart("\", "/")
  if (-not $relativeDir) { return $false }
  return (($relativeDir -split "[\\/]") -contains "Gmail")
}

function Get-PreferredArticleFiles {
  param([System.IO.DirectoryInfo]$IssueDir, [string]$IssueId)
  $candidates = Get-ChildItem -Path $IssueDir.FullName -Recurse -File -Filter "*.docx" |
    Where-Object { -not (Should-SkipDoc $_) -and -not (Test-NestedIssueDoc $_ $IssueDir) }

  $groups = @{}
  foreach ($file in $candidates) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $sourceId = Get-SourceId $IssueId $stem
    $category = (Get-CategoryInfo $stem).Category
    $key = "$sourceId::$category"
    if (-not $groups.ContainsKey($key)) {
      $groups[$key] = New-Object System.Collections.Generic.List[object]
    }
    $groups[$key].Add($file)
  }

  $preferred = New-Object System.Collections.Generic.List[object]
  foreach ($key in $groups.Keys) {
    $items = @($groups[$key].ToArray())
    $gmailItems = @($items | Where-Object { Test-InGmailFolder $_ $IssueDir } | Sort-Object Name, FullName)
    if ($gmailItems.Count -gt 0) {
      $preferred.Add($gmailItems[0])
      foreach ($replaced in ($items | Where-Object { $_.FullName -ne $gmailItems[0].FullName })) {
        $script:validationItems.Add(@{
          issueId = $IssueId
          file = $replaced.FullName
          severity = "warning"
          type = "gmail-source-replaced"
          message = "同 sourceId 已採用 Gmail 版本：$($gmailItems[0].FullName)"
        })
      }
    } else {
      foreach ($item in ($items | Sort-Object Name, FullName)) {
        $preferred.Add($item)
      }
    }
  }

  return @($preferred | Sort-Object Name, FullName)
}

$issueDirs = Get-ChildItem -Path $sourceRoot -Recurse -Directory |
  Where-Object { $_.Name -match "^(20\d{4})" -and -not (Test-SkippedDirectoryPath $_) } |
  Sort-Object Name -Descending

$articles = New-Object System.Collections.Generic.List[object]
$issues = New-Object System.Collections.Generic.List[object]
$seenSlugs = @{}
$validationItems = New-Object System.Collections.Generic.List[object]
$cacheHitCount = 0
$cacheMissCount = 0
$changedImportFiles = New-Object System.Collections.Generic.List[object]
$approvalMap = @{}
$correctionMap = @{}
$approvalFingerprint = ""
if (Test-Path -LiteralPath $reviewApprovalsPath) {
  try {
    $approvalFingerprint = Get-FileContentHash $reviewApprovalsPath
    $approvalData = Get-Content -LiteralPath $reviewApprovalsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @($approvalData.approvals)) {
      if ($entry.id) { $approvalMap[$entry.id] = $entry }
    }
    foreach ($entry in @($approvalData.corrections)) {
      if ($entry.id) { $correctionMap[$entry.id] = $entry }
    }
  } catch {
    Write-Warning "Cannot read review approvals: $reviewApprovalsPath ($($_.Exception.Message))"
  }
}

$cacheMap = @{}
$nextCacheEntries = @{}
if (Test-Path -LiteralPath $importCachePath) {
  try {
    $cacheData = Get-Content -LiteralPath $importCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @($cacheData.entries)) {
      if ($entry.signature -and $entry.signature.key) {
        $cacheMap[[string]$entry.signature.key] = $entry
      }
    }
    Write-Host "Loaded article import cache: $($cacheMap.Count) entries."
  } catch {
    Write-Warning "Cannot read article import cache: $importCachePath ($($_.Exception.Message))"
  }
}

foreach ($issueDir in $issueDirs) {
  $issueId = ([regex]::Match($issueDir.Name, "20\d{4}")).Value
  $year = $issueId.Substring(0, 4)
  $month = $issueId.Substring(4, 2)
  $issueNumber = Get-IssueNumber $issueId
  $files = Get-PreferredArticleFiles $issueDir $issueId
  $images = Copy-IssueImages $issueId $issueDir
  $imageIndex = [ref]($images.Count + 1)

  $issueArticles = New-Object System.Collections.Generic.List[object]
  $order = 0
  foreach ($file in $files) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $sourceId = Get-SourceId $issueId $stem
    $signature = Get-FileSignature $file $sourceRoot $importCacheVersion $approvalFingerprint
    $cachedEntry = $cacheMap[[string]$signature.key]
    if ((Test-CacheSignatureMatch $cachedEntry $signature) -and $cachedEntry.article) {
      $cacheHitCount++
      $cachedArticle = Normalize-CachedArticle $cachedEntry.article
      $cachedArticle["order"] = $order
      if ($cachedArticle.slug) {
        if ($seenSlugs.ContainsKey($cachedArticle.slug)) {
          $seenSlugs[$cachedArticle.slug] += 1
        } else {
          $seenSlugs[$cachedArticle.slug] = 1
        }
      }
      $issueArticles.Add($cachedArticle)
      foreach ($cachedValidation in @(ConvertTo-ArrayValue $cachedEntry.validationItems)) {
        $validationItems.Add((ConvertTo-PlainObject $cachedValidation))
      }
      $nextCacheEntries[[string]$signature.key] = @{
        signature = $signature
        article = $cachedArticle
        validationItems = @(ConvertTo-ArrayValue $cachedEntry.validationItems)
      }
      $order++
      continue
    }
    $cacheMissCount++
    $changedImportFiles.Add([pscustomobject]@{
      issueId = $issueId
      fileName = $file.Name
      relativePath = (Get-RelativePath $Root $file.FullName)
      status = if ($cachedEntry) { "updated" } else { "new" }
    })

    $validationStartIndex = $validationItems.Count
    $docxContent = Read-DocxContent $file $issueId (Join-Path $publicArticles $issueId) $imageIndex
    $paragraphs = $docxContent.Paragraphs
    if (-not $paragraphs -or $paragraphs.Count -eq 0) { continue }

    $title = Get-CleanTitle $stem
    $bodyParagraphs = $paragraphs
    $hasHeader = $false
    $headerAuthor = ""
    $legacyCategoryInfo = Get-CategoryInfo "$stem $title $($paragraphs[0])"

    $template = Parse-ArticleTemplate $paragraphs $issueId
    if ($template.HasTemplate) {
      if (-not $template.IsValid) {
        $validationItems.Add(@{
          issueId = $issueId
          file = $file.FullName
          severity = "error"
          type = "template-invalid"
          message = ($template.Errors -join "；")
        })
        continue
      }
      $title = $template.Title
      $headerAuthor = $template.Author
      $bodyParagraphs = $paragraphs | Select-Object -Skip $template.BodyStart
    } else {
      $validationItems.Add(@{
        issueId = $issueId
        file = $file.FullName
        severity = "warning"
        type = "legacy-template-missing"
        message = "舊格式文章未含投稿模板，已用保守 legacy 規則匯入"
      })
      $legacyHeader = Parse-LegacyHeader $paragraphs $title $legacyCategoryInfo.Category
      $title = $legacyHeader.Title
      $headerAuthor = $legacyHeader.Author
      $bodyParagraphs = $legacyHeader.BodyParagraphs
      $hasHeader = $legacyHeader.HasHeader
      if ($legacyHeader.Category) {
        $legacyCategoryInfo = @{
          Category = $legacyHeader.Category
          Tags = @($legacyHeader.Tags)
        }
      }
    }
    $articleReviewId = "$issueId::$($file.FullName)"
    $wordReviewId = "word::$($file.FullName)"
    $correction = $null
    if ($correctionMap.ContainsKey($articleReviewId)) {
      $correction = $correctionMap[$articleReviewId]
    } elseif ($correctionMap.ContainsKey($wordReviewId)) {
      $correction = $correctionMap[$wordReviewId]
    }

    $parsedTitleBeforeCorrection = $title
    $correctedTitle = Get-ReviewCorrectionValue $correction "title"
    $correctedAuthor = Get-ReviewCorrectionValue $correction "author"
    $correctedCategory = Get-ReviewCorrectionValue $correction "category"
    $correctedDate = Get-ReviewCorrectionValue $correction "date"
    if ($correctedTitle) {
      $parsedTitleKey = Normalize-ArticleText $parsedTitleBeforeCorrection
      $correctedTitleKey = Normalize-ArticleText $correctedTitle
      $parsedTitleInSource = @($paragraphs | Where-Object { (Normalize-ArticleText $_) -eq $parsedTitleKey }).Count -gt 0
      $parsedTitleInBody = @($bodyParagraphs | Where-Object { (Normalize-ArticleText $_) -eq $parsedTitleKey }).Count -gt 0
      if (
        $parsedTitleKey -and
        $parsedTitleKey -ne $correctedTitleKey -and
        $parsedTitleInSource -and
        -not $parsedTitleInBody -and
        (Test-BodyParagraphLike $parsedTitleBeforeCorrection)
      ) {
        $bodyParagraphs = @($parsedTitleBeforeCorrection) + @($bodyParagraphs)
      }
      $title = $correctedTitle
    }
    $categoryInfo = if ($template.HasTemplate) {
      @{ Category = $template.Category; Tags = @($template.Category) }
    } else {
      $legacyCategoryInfo
    }
    if ($correctedCategory) {
      $categoryInfo = @{
        Category = $correctedCategory
        Tags = @($correctedCategory)
      }
    }
    $author = $headerAuthor
    if (-not $template.HasTemplate) {
      foreach ($p in $paragraphs | Select-Object -First 5) {
        if (-not $author -and $p -match "^(文|整理|撰文|作者|編輯|口述|彙整)[／/：:]") { $author = $p; break }
      }
    }
    if ($author) {
      $author = Convert-LegacyAuthorLine $author
    }
    if ($correctedAuthor) {
      $author = Convert-LegacyAuthorLine $correctedAuthor
    }
    if (-not $author) {
      $validationItems.Add(@{
        issueId = $issueId
        file = $file.FullName
        severity = "warning"
        type = "missing-author"
        message = "缺少作者，已留空"
      })
    }

    $titleKey = Normalize-ArticleText $title
    $authorKey = Normalize-ArticleText (Convert-LegacyAuthorLine $author)
    $bodyParagraphs = @($bodyParagraphs | Where-Object {
      $paragraphText = ([string]$_).Trim()
      $paragraphKey = Normalize-ArticleText $paragraphText
      $paragraphAuthorKey = Normalize-ArticleText (Convert-LegacyAuthorLine $paragraphText)
      $paragraphText -notmatch "^圖片來源" -and
        $paragraphText -notmatch "^圖片標題[：:]" -and
        -not (Test-TemplateControlLine $paragraphText) -and
        $paragraphText -notmatch "^\d{4}[./-]\d{1,2}[./-]\d{1,2}$" -and
        $paragraphKey -ne $titleKey -and
        (-not $authorKey -or $paragraphText.Length -gt 64 -or ($paragraphKey -ne $authorKey -and $paragraphAuthorKey -ne $authorKey))
    })

    $slug = Get-Slug $issueId $sourceId $title
    if ($seenSlugs.ContainsKey($slug)) {
      $seenSlugs[$slug] += 1
      $slug = "$slug-$($seenSlugs[$slug])"
    } else {
      $seenSlugs[$slug] = 1
    }

    $blockWarnings = New-Object System.Collections.Generic.List[string]
    foreach ($warning in $docxContent.Warnings) { $blockWarnings.Add($warning) }
    $bodyBlocks = if ($template.HasTemplate -and $template.BodyMarker) {
      Select-BlocksAfterText $docxContent.Blocks $template.BodyMarker
    } else {
      Select-BodyBlocks $docxContent.Blocks $bodyParagraphs
    }
    $bodyBlocks = Remove-HeaderLikeBlocks $bodyBlocks $title $author $categoryInfo.Category
    $bodyBlocks = Resolve-ImageCaptions $bodyBlocks $blockWarnings
    $contentBlocks = Convert-BlocksToDisplayBlocks $bodyBlocks
    foreach ($warning in $blockWarnings) {
      $validationItems.Add(@{
        issueId = $issueId
        file = $file.FullName
        severity = "warning"
        type = "content-warning"
        message = $warning
      })
    }
    $articleImages = @($contentBlocks | Where-Object { $_.type -eq "image" })
    $docxImages = @($docxContent.Images)
    $heroImage = ""
    $heroCaption = ""
    if ($articleImages.Count -gt 0) {
      $heroImage = $articleImages[0].src
      $heroCaption = $articleImages[0].caption
    } elseif ($docxImages.Count -gt 0) {
      $heroImage = $docxImages[0].src
      $heroCaption = $docxImages[0].caption
    }
    $sourceCaption = Get-ImageSourceCaption $paragraphs
    if (-not $heroCaption -and $sourceCaption) {
      $heroCaption = $sourceCaption
    } elseif (-not $heroCaption -and $template.HasTemplate -and $template.ImageSource) {
      $heroCaption = "圖片來源 / $($template.ImageSource)"
    }
    $allArticleImages = @($articleImages)
    if ($docxImages.Count -gt 0) {
      foreach ($image in $docxImages) {
        if (-not (@($allArticleImages | Where-Object { $_.src -eq $image.src }).Count -gt 0)) {
          $allArticleImages += $image
        }
      }
    }

    $readMinutes = [Math]::Max(2, [Math]::Ceiling((($bodyParagraphs | ForEach-Object { $_.Length } | Measure-Object -Sum).Sum) / 650))
    $article = @{
      slug = $slug
      sourceId = $sourceId
      sourceUrl = ""
      issueId = $issueId
      title = $title
      category = $categoryInfo.Category
      author = $author
      date = if ($correctedDate) { $correctedDate } elseif ($template.HasTemplate) { $template.Date } else { "$year.$month.10" }
      issue = "第$issueNumber`期 / $year.$month`電子報"
      readTime = "約 $readMinutes 分鐘"
      homeAnchor = "#article-$slug"
      excerpt = Get-Excerpt $bodyParagraphs
      image = $heroImage
      imageCaption = $heroCaption
      sections = @(Split-Sections $bodyParagraphs)
      contentBlocks = @($contentBlocks)
      images = @($allArticleImages)
      tags = $categoryInfo.Tags
      order = $order
    }
    $issueArticles.Add($article)
    $fileValidationItems = New-Object System.Collections.Generic.List[object]
    for ($validationIndex = $validationStartIndex; $validationIndex -lt $validationItems.Count; $validationIndex++) {
      $fileValidationItems.Add($validationItems[$validationIndex])
    }
    $nextCacheEntries[[string]$signature.key] = @{
      signature = $signature
      article = $article
      validationItems = @($fileValidationItems.ToArray())
    }
    $order++
  }
  $orderedIssueArticles = @($issueArticles | Sort-Object @{ Expression = { if ($_.category -eq "編輯小語") { 0 } else { 1 } } }, order, title)
  for ($i = 0; $i -lt $orderedIssueArticles.Count; $i++) {
    $orderedIssueArticles[$i]["order"] = $i
    $articles.Add($orderedIssueArticles[$i])
  }
}

Apply-PixabayFallbackImages $articles

$issues = New-Object System.Collections.Generic.List[object]
$issueIds = $articles |
  ForEach-Object { $_.issueId } |
  Sort-Object -Descending -Unique

foreach ($id in $issueIds) {
  $year = $id.Substring(0, 4)
  $month = $id.Substring(4, 2)
  $issueNumber = Get-IssueNumber $id
  $issueArticles = @($articles | Where-Object { $_.issueId -eq $id } | Sort-Object order)
  if ($issueArticles.Count -eq 0) { continue }
  $coverImage = ($issueArticles | Where-Object { $_.image -and $_.image -ne $logoPath } | Select-Object -First 1).image
  if (-not $coverImage) { $coverImage = $logoPath }
  $issues.Add(@{
    id = $id
    label = "$year.$month 電子報"
    issueNumber = "第$issueNumber`期"
    date = "$year.$month"
    href = "/issues/$id/"
    articleCount = $issueArticles.Count
    image = $coverImage
    title = $issueArticles[0].title
  })
}

$knownCategories = New-Object System.Collections.Generic.HashSet[string]
[void]$knownCategories.Add("專欄文章")
foreach ($rule in $categoryRules) { [void]$knownCategories.Add($rule.Category) }

foreach ($article in $articles) {
  if (-not $knownCategories.Contains($article.category)) {
    $validationItems.Add(@{
      issueId = $article.issueId
      file = $article.sourceId
      severity = "warning"
      type = "unknown-category"
      message = "分類不在既有分類清單：$($article.category)"
    })
  }
  if (-not $article.author) {
    $validationItems.Add(@{
      issueId = $article.issueId
      file = $article.sourceId
      severity = "warning"
      type = "missing-author"
      message = "文章缺少作者：$($article.title)"
    })
  }
}

$duplicateGroups = $articles |
  Group-Object issueId, title |
  Where-Object { $_.Count -gt 1 }
foreach ($group in $duplicateGroups) {
  $validationItems.Add(@{
    issueId = ($group.Group | Select-Object -First 1).issueId
    file = (($group.Group | ForEach-Object { $_.sourceId }) -join ", ")
    severity = "warning"
    type = "possible-duplicate"
    message = "同一期內疑似重複文章標題：$(($group.Group | Select-Object -First 1).title)"
  })
}

$reportDir = Join-Path $Root "reports"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$importChangedFilesReport = @{
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  totalChanged = $changedImportFiles.Count
  changedFiles = @($changedImportFiles.ToArray())
}
$importChangedReportJson = $importChangedFilesReport | ConvertTo-Json -Depth 8
$importChangedReportPath = Join-Path $reportDir "import-changed-files.json"
$importChangedReportJson | Set-Content -LiteralPath $importChangedReportPath -Encoding UTF8
$publicDataDir = Join-Path $Root "public/data"
New-Item -ItemType Directory -Force -Path $publicDataDir | Out-Null
$importChangedReportJson | Set-Content -LiteralPath (Join-Path $publicDataDir "import-changed-files.json") -Encoding UTF8
$reportJsonPath = Join-Path $reportDir "import-validation.json"
$reportMdPath = Join-Path $reportDir "import-validation.md"
$validationItems | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportJsonPath -Encoding UTF8
$reportLines = New-Object System.Collections.Generic.List[string]
$reportLines.Add("# 匯入校驗報告")
$reportLines.Add("")
$reportLines.Add("產生時間：$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")")
$reportLines.Add("")
$reportLines.Add("總筆數：$($validationItems.Count)")
$reportLines.Add("")
foreach ($item in $validationItems) {
  $reportLines.Add("- [$($item.severity)] $($item.issueId) / $($item.type) / $($item.file)：$($item.message)")
}
$reportLines | Set-Content -LiteralPath $reportMdPath -Encoding UTF8

$reviewItems = New-Object System.Collections.Generic.List[object]
$validationGroupMap = @{}
foreach ($item in $validationItems) {
  $key = "$($item.issueId):::$($item.file)"
  if (-not $validationGroupMap.ContainsKey($key)) {
    $validationGroupMap[$key] = New-Object System.Collections.Generic.List[object]
  }
  $validationGroupMap[$key].Add($item)
}
foreach ($key in $validationGroupMap.Keys) {
  $groupItems = @($validationGroupMap.Item($key).ToArray())
  $first = $groupItems | Select-Object -First 1
  $fileKey = [string]$first.file
  $sourceModified = ""
  if ($fileKey -and (Test-Path -LiteralPath $fileKey)) {
    $sourceModified = (Get-Item -LiteralPath $fileKey).LastWriteTimeUtc.ToString("o")
  }
  $article = $articles |
    Where-Object {
      $_.issueId -eq $first.issueId -and
      ($fileKey -eq $_.sourceId -or $fileKey -match [regex]::Escape($_.sourceId))
    } |
    Select-Object -First 1
  $reviewId = "$($first.issueId)::${fileKey}"
  $hasError = @($groupItems | Where-Object { $_.severity -eq "error" }).Count -gt 0
  $approval = $approvalMap[$reviewId]
  $isApproved = $false
  if ($approval) {
    $approvedModified = [string]$approval.sourceModified
    $isApproved = (-not $approvedModified -or $approvedModified -eq $sourceModified)
  }
  $status = if ($hasError) { "error" } elseif ($isApproved) { "approved" } else { "needs-review" }
  $reviewItems.Add(@{
    id = $reviewId
    status = $status
    issueId = $first.issueId
    file = $fileKey
    sourceModified = $sourceModified
    slug = if ($article) { $article.slug } else { "" }
    sourceId = if ($article) { $article.sourceId } else { "" }
    title = if ($article) { $article.title } else { "" }
    category = if ($article) { $article.category } else { "" }
    author = if ($article) { $article.author } else { "" }
    date = if ($article) { $article.date } else { "" }
    excerpt = if ($article) { $article.excerpt } else { "" }
    image = if ($article) { $article.image } else { "" }
    messages = @($groupItems | ForEach-Object {
      @{
        severity = $_.severity
        type = $_.type
        message = $_.message
      }
    })
  })
}

$jsonDepth = 20
$articlesJson = $articles | ConvertTo-Json -Depth $jsonDepth
$issuesJson = $issues | ConvertTo-Json -Depth $jsonDepth
$sortedReviewItems = @($reviewItems | Sort-Object @{ Expression = { if ($_.status -eq "error") { 0 } elseif ($_.status -eq "needs-review") { 1 } else { 2 } } }, issueId, file)
$reviewJson = ConvertTo-Json -InputObject $sortedReviewItems -Depth $jsonDepth
$cacheEntries = @($nextCacheEntries.Values | Sort-Object { [string]$_.signature.key })
$cachePayload = @{
  version = $importCacheVersion
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  entries = $cacheEntries
}
New-Item -ItemType Directory -Force -Path $importCacheDir | Out-Null
$cachePayload | ConvertTo-Json -Depth $jsonDepth | Set-Content -LiteralPath $importCachePath -Encoding UTF8
$content = @"
import type { Article, IssueArchive } from "./articles";

export const generatedArticles = $articlesJson satisfies Article[];

export const generatedIssues = $issuesJson satisfies IssueArchive[];
"@

Set-Content -LiteralPath $generatedPath -Encoding UTF8 -Value $content
$reviewContent = @"
import type { ReviewItem } from "./review";

export const generatedReviewItems = $reviewJson satisfies ReviewItem[];
"@

Set-Content -LiteralPath $generatedReviewPath -Encoding UTF8 -Value $reviewContent
Write-Host "Generated $($articles.Count) articles across $($issues.Count) issues."
Write-Host "Article import cache: $cacheHitCount hit(s), $cacheMissCount rebuilt."
Write-Host "Changed Word files: $($changedImportFiles.Count)"
