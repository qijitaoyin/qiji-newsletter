param(
  [string]$PublishFile = "review-publish.json",
  [string]$OverridesFile = "src/data/editorialOverrides.json",
  [string]$PublishStateFile = "src/data/publishState.json"
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

$publish = Read-JsonFile $PublishFile '{ "metadataOverrides": { "quotes": {}, "tags": {} } }'
$overrides = Read-JsonFile $OverridesFile '{ "quotes": {}, "tags": {} }'
$publishState = Read-JsonFile $PublishStateFile '{ "publicLatestIssueId": "202605", "reviewIssueId": "", "publishedAt": "" }'

if ($publish.status -eq "has-open-tasks") {
  Write-Warning "The publish file still contains open review tasks. Continuing because this may be intentional."
}

Ensure-ObjectProperty $overrides "quotes"
Ensure-ObjectProperty $overrides "tags"
$publishedIssueId = Resolve-PublishIssueId $publish

$quoteCount = 0
$tagCount = 0

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

$tags = $publish.metadataOverrides.tags
if ($tags) {
  foreach ($prop in $tags.PSObject.Properties) {
    $slug = [string]$prop.Name
    $value = @($prop.Value) | ForEach-Object { [string]$_ } | Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    }
    if ([string]::IsNullOrWhiteSpace($slug) -or $value.Count -eq 0) {
      continue
    }

    if ($overrides.tags.PSObject.Properties[$slug]) {
      $overrides.tags.$slug = $value
    } else {
      $overrides.tags | Add-Member -MemberType NoteProperty -Name $slug -Value $value
    }
    $tagCount += 1
  }
}

$directory = Split-Path -Parent $OverridesFile
if ($directory -and -not (Test-Path -LiteralPath $directory)) {
  New-Item -ItemType Directory -Path $directory | Out-Null
}

$json = $overrides | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText((Resolve-OutputPath $OverridesFile), $json, [System.Text.UTF8Encoding]::new($false))

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
Write-Host "Tag overrides: $tagCount"
Write-Host "Updated: $OverridesFile"
Write-Host "Updated: $PublishStateFile"
