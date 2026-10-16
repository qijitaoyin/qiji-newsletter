function Get-PixabayCandidateTags {
  param([object]$Candidate)

  $rawTags = [string]$Candidate.tags
  if ([string]::IsNullOrWhiteSpace($rawTags)) { return @() }
  return @(
    $rawTags -split "," |
      ForEach-Object { $_.Trim().ToLowerInvariant() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
}

function Test-NaturalLandscapePixabayCandidate {
  param([object]$Candidate)

  if ($Candidate.type -and [string]$Candidate.type -ne "photo") { return $false }

  $imageWidth = [double]$Candidate.imageWidth
  $imageHeight = [double]$Candidate.imageHeight
  if ($imageWidth -gt 0 -and $imageHeight -gt 0 -and ($imageWidth / $imageHeight) -lt 1.35) {
    return $false
  }

  $tags = @(Get-PixabayCandidateTags $Candidate)
  if ($tags.Count -eq 0) { return $false }
  $tagText = " " + ($tags -join " ") + " "

  $allowedTags = @(
    "nature", "landscape", "scenery", "mountain", "mountains", "forest", "woods", "tree", "trees",
    "lake", "river", "waterfall", "ocean", "sea", "beach", "coast", "sky", "cloud", "clouds",
    "sunrise", "sunset", "valley", "meadow", "grass", "field", "flower", "flowers", "wilderness",
    "desert", "snow", "winter", "autumn", "spring", "summer", "island", "cliff", "rock", "rocks"
  )

  $blockedTerms = @(
    "people", "person", "human", "man", "woman", "child", "girl", "boy", "portrait", "face", "body",
    "silhouette", "couple", "family", "crowd", "umbrella",
    "fantasy", "surreal", "dream", "dreamlike", "digital art", "illustration", "render", "3d", "ai generated",
    "generative ai", "photomanipulation", "manipulation", "composite", "concept art", "abstract",
    "moon", "planet", "space", "galaxy", "comet", "meteor", "spaceship",
    "city", "urban", "street", "road", "highway", "bridge", "building", "architecture", "house",
    "home", "room", "interior", "church", "temple", "tower", "castle", "car", "vehicle", "bus",
    "train", "bicycle", "bike", "boat", "ship", "airplane", "plane", "table", "chair", "bench",
    "fence", "lamp", "computer", "phone", "robot", "food", "coffee", "cup", "book", "money",
    "business", "office"
  )

  foreach ($term in $blockedTerms) {
    if ($tagText.Contains(" $term ")) { return $false }
  }

  foreach ($tag in $tags) {
    if ($allowedTags -contains $tag) { return $true }
  }
  return $false
}

function Get-PixabayCandidateQualityScore {
  param([object]$Candidate)

  $tags = @(Get-PixabayCandidateTags $Candidate)
  $score = 0
  foreach ($tag in $tags) {
    if (@("nature", "landscape", "scenery", "wilderness") -contains $tag) {
      $score += 8
    } elseif (@("mountain", "mountains", "forest", "woods", "lake", "river", "waterfall", "ocean", "sea", "valley", "meadow") -contains $tag) {
      $score += 4
    }
  }

  $width = [double]$Candidate.imageWidth
  $height = [double]$Candidate.imageHeight
  if ($width -gt 0 -and $height -gt 0) {
    $ratio = $width / $height
    if ($ratio -ge 1.5 -and $ratio -le 2.1) { $score += 6 }
  }
  return $score
}
