param(
  [string]$PublishFile = "review-publish.json",
  [string]$OverridesFile = "src/data/editorialOverrides.json",
  [string]$PublishStateFile = "src/data/publishState.json",
  [string]$FeedbackFile = "src/data/aiFeedbackExamples.json"
)

$ErrorActionPreference = "Stop"

function Read-JsonFile($Path, $DefaultJson) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return $DefaultJson | ConvertFrom-Json
  }

  $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return $DefaultJson | ConvertFrom-Json
  }

  return $raw | ConvertFrom-Json
}

function Ensure-ObjectProperty($Object, $Name) {
  if (-not $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value ([pscustomobject]@{})
  }
}

function Resolve-OutputPath($Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return Join-Path (Get-Location) $Path
}

function Resolve-PublishIssueId($Publish) {
  $issueId = [string]$Publish.issueId
  if ($issueId -and $issueId -ne "latest") {
    return $issueId
  }

  $candidates = New-Object System.Collections.Generic.List[string]
  foreach ($entry in @($Publish.reports) + @($Publish.openReports)) {
    foreach ($value in @($entry.articleSlug, $entry.articleUrl)) {
      $text = [string]$value
      if ($text -match "(20\d{4})") {
        $candidates.Add($Matches[1])
      }
    }
  }

  if ($candidates.Count -gt 0) {
    return @($candidates | Sort-Object -Descending | Select-Object -First 1)[0]
  }

  throw "Cannot determine published issue id. The publish payload should include issueId like 202607."
}

if (-not (Test-Path -LiteralPath $PublishFile)) {
  throw "Publish file not found: $PublishFile. Generate it from /review/ or provide it with -PublishFile."
}

$publish = Read-JsonFile $PublishFile '{ "metadataOverrides": { "quotes": {}, "summaries": {}, "categories": {}, "tags": {} } }'
$overrides = Read-JsonFile $OverridesFile '{ "quotes": {}, "summaries": {}, "categories": {}, "tags": {} }'
$publishState = Read-JsonFile $PublishStateFile '{ "publicLatestIssueId": "202605", "reviewIssueId": "", "publishedAt": "" }'
$feedback = Read-JsonFile $FeedbackFile '{ "version": 1, "examples": [] }'

if ($publish.status -eq "has-open-tasks") {
  Write-Warning "The publish file still contains open review tasks. Continuing because this may be intentional."
}

Ensure-ObjectProperty $overrides "quotes"
Ensure-ObjectProperty $overrides "summaries"
Ensure-ObjectProperty $overrides "categories"
Ensure-ObjectProperty $overrides "tags"
if (-not $feedback.PSObject.Properties["examples"]) {
  $feedback | Add-Member -MemberType NoteProperty -Name "examples" -Value @()
}
$publishedIssueId = Resolve-PublishIssueId $publish

$quoteCount = 0
$summaryCount = 0
$categoryCount = 0
$tagCount = 0
$feedbackCount = 0

$quotes = $publish.metadataOverrides.quotes
if ($quotes) {
  foreach ($prop in $quotes.PSObject.Properties) {
    $slug = [string]$prop.Name
    $value = [string]$prop.Value
    if ([string]::IsNullOrWhiteSpace($slug) -or [string]::IsNullOrWhiteSpace($value)) {
      continue
    }

    if ($overrides.quotes.PSObject.Properties[$slug]) {
      $overrides.quotes.$slug = $value
    } else {
      $overrides.quotes | Add-Member -MemberType NoteProperty -Name $slug -Value $value
    }
    $quoteCount += 1
  }
}

$summaries = $publish.metadataOverrides.summaries
if ($summaries) {
  foreach ($prop in $summaries.PSObject.Properties) {
    $slug = [string]$prop.Name
    $value = [string]$prop.Value
    if ([string]::IsNullOrWhiteSpace($slug) -or [string]::IsNullOrWhiteSpace($value)) {
      continue
    }

    if ($overrides.summaries.PSObject.Properties[$slug]) {
      $overrides.summaries.$slug = $value
    } else {
      $overrides.summaries | Add-Member -MemberType NoteProperty -Name $slug -Value $value
    }
    $summaryCount += 1
  }
}

$categories = $publish.metadataOverrides.categories
if ($categories) {
  foreach ($prop in $categories.PSObject.Properties) {
    $slug = [string]$prop.Name
    $value = [string]$prop.Value
    if ([string]::IsNullOrWhiteSpace($slug) -or [string]::IsNullOrWhiteSpace($value)) {
      continue
    }

    if ($overrides.categories.PSObject.Properties[$slug]) {
      $overrides.categories.$slug = $value
    } else {
      $overrides.categories | Add-Member -MemberType NoteProperty -Name $slug -Value $value
    }
    $categoryCount += 1
  }
}

$tags = $publish.metadataOverrides.tags
if ($tags) {
  foreach ($prop in $tags.PSObject.Properties) {
    $slug = [string]$prop.Name
    $value = [object[]](@($prop.Value) | ForEach-Object { [string]$_ } | Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    })
    if ([string]::IsNullOrWhiteSpace($slug) -or $value.Count -eq 0) {
      continue
    }

    if ($overrides.tags.PSObject.Properties[$slug]) {
      $overrides.tags.$slug = @($value)
    } else {
      $overrides.tags | Add-Member -MemberType NoteProperty -Name $slug -Value @($value)
    }
    $tagCount += 1
  }
}

$existingFeedback = @($feedback.examples) | Where-Object { $_ }
$newFeedback = New-Object System.Collections.Generic.List[object]
foreach ($report in @($publish.reports)) {
  $hasMetadata = $report.metadataQuote -or $report.metadataSummary -or $report.metadataCategory -or @($report.metadataTags).Count -gt 0
  if (-not $hasMetadata) {
    continue
  }

  $feedbackId = if ($report.id) { [string]$report.id } else { "$($report.articleSlug)-$($report.metadataUpdatedAt)" }
  $newFeedback.Add([pscustomobject]@{
    id = $feedbackId
    slug = [string]$report.articleSlug
    title = [string]$report.articleTitle
    category = [string]$report.articleCategory
    original = [pscustomobject]@{
      quote = [string]$report.originalMetadata.quote
      summary = [string]$report.originalMetadata.summary
      category = [string]$report.originalMetadata.category
      tags = @($report.originalMetadata.tags)
    }
    corrected = [pscustomobject]@{
      quote = [string]$report.metadataQuote
      summary = [string]$report.metadataSummary
      category = [string]$report.metadataCategory
      tags = @($report.metadataTags)
    }
    reason = [string]$report.comment
    source = "review-metadata-override"
    createdAt = if ($report.metadataUpdatedAt) { [string]$report.metadataUpdatedAt } else { (Get-Date).ToUniversalTime().ToString("o") }
  })
}

if ($newFeedback.Count -gt 0) {
  $newIds = @{}
  foreach ($item in $newFeedback) { $newIds[[string]$item.id] = $true }
  $feedback.examples = @(
    $existingFeedback | Where-Object { -not $newIds.ContainsKey([string]$_.id) }
  ) + @($newFeedback.ToArray())
  $feedbackCount = $newFeedback.Count
}

$directory = Split-Path -Parent $OverridesFile
if ($directory -and -not (Test-Path -LiteralPath $directory)) {
  New-Item -ItemType Directory -Path $directory | Out-Null
}

$json = $overrides | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText((Resolve-OutputPath $OverridesFile), $json, [System.Text.UTF8Encoding]::new($false))

$feedbackDirectory = Split-Path -Parent $FeedbackFile
if ($feedbackDirectory -and -not (Test-Path -LiteralPath $feedbackDirectory)) {
  New-Item -ItemType Directory -Path $feedbackDirectory | Out-Null
}
$feedbackJson = $feedback | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText((Resolve-OutputPath $FeedbackFile), $feedbackJson, [System.Text.UTF8Encoding]::new($false))

$publishState.publicLatestIssueId = $publishedIssueId
$publishState.reviewIssueId = $publishedIssueId
$publishState.publishedAt = (Get-Date).ToUniversalTime().ToString("o")
$stateDirectory = Split-Path -Parent $PublishStateFile
if ($stateDirectory -and -not (Test-Path -LiteralPath $stateDirectory)) {
  New-Item -ItemType Directory -Path $stateDirectory | Out-Null
}
$stateJson = $publishState | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText((Resolve-OutputPath $PublishStateFile), $stateJson, [System.Text.UTF8Encoding]::new($false))

Write-Host "Applied review publish file."
Write-Host "Published issue: $publishedIssueId"
Write-Host "Quote overrides: $quoteCount"
Write-Host "Summary overrides: $summaryCount"
Write-Host "Category overrides: $categoryCount"
Write-Host "Tag overrides: $tagCount"
Write-Host "AI feedback examples: $feedbackCount"
Write-Host "Updated: $OverridesFile"
Write-Host "Updated: $FeedbackFile"
Write-Host "Updated: $PublishStateFile"
