$ErrorActionPreference = "Stop"
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("qiji-review-scope-" + [guid]::NewGuid().ToString("N"))
$global:qijiReviewScopeCommands = New-Object System.Collections.Generic.List[string]

function global:rclone {
  $arguments = @($args)
  $global:LASTEXITCODE = 0
  if ($arguments[0] -eq "lsf") {
    @("202508/", "202610/", "202611/", "draft/")
    return
  }
  $global:qijiReviewScopeCommands.Add(($arguments -join " "))
}

try {
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $selection = Join-Path $root "latest.json"
  & (Join-Path $PSScriptRoot "sync_google_drive.ps1") `
    -Remote "mock:issues" `
    -Destination (Join-Path $root "latest") `
    -Scope "latest" `
    -PublicLatestIssueId "202610" `
    -SelectionFile $selection
  $latest = Get-Content -LiteralPath $selection -Raw | ConvertFrom-Json
  if (@($latest.selectedIssueIds).Count -ne 1 -or $latest.selectedIssueIds[0] -ne "202611") {
    throw "Latest scope did not select only 202611."
  }
  if ($global:qijiReviewScopeCommands.Count -ne 1 -or $global:qijiReviewScopeCommands[0] -notmatch 'sync mock:issues/202611') {
    throw "Latest scope synced unexpected issue folders."
  }

  $global:qijiReviewScopeCommands.Clear()
  $selection = Join-Path $root "latest-published.json"
  & (Join-Path $PSScriptRoot "sync_google_drive.ps1") `
    -Remote "mock:issues" `
    -Destination (Join-Path $root "latest-published") `
    -Scope "latest" `
    -PublicLatestIssueId "202611" `
    -SelectionFile $selection
  $latestPublished = Get-Content -LiteralPath $selection -Raw | ConvertFrom-Json
  if (@($latestPublished.selectedIssueIds).Count -ne 1 -or $latestPublished.selectedIssueIds[0] -ne "202611") {
    throw "Latest scope must select 202611 even after it is published."
  }
  if ($global:qijiReviewScopeCommands.Count -ne 1 -or $global:qijiReviewScopeCommands[0] -notmatch 'sync mock:issues/202611') {
    throw "Latest published scope synced unexpected issue folders."
  }

  $global:qijiReviewScopeCommands.Clear()
  $selection = Join-Path $root "published.json"
  & (Join-Path $PSScriptRoot "sync_google_drive.ps1") `
    -Remote "mock:issues" `
    -Destination (Join-Path $root "published") `
    -Scope "published" `
    -PublicLatestIssueId "202610" `
    -SelectionFile $selection
  $published = Get-Content -LiteralPath $selection -Raw | ConvertFrom-Json
  if ((@($published.selectedIssueIds) -join ',') -ne "202508,202610") {
    throw "Published scope selected unexpected issue folders."
  }
  if ($global:qijiReviewScopeCommands.Count -ne 2) {
    throw "Published scope did not sync both published issue folders."
  }

  $global:qijiReviewScopeCommands.Clear()
  $selection = Join-Path $root "new-legacy.json"
  & (Join-Path $PSScriptRoot "sync_google_drive.ps1") `
    -Remote "mock:issues" `
    -Destination (Join-Path $root "new-legacy") `
    -Scope "new-legacy" `
    -PublicLatestIssueId "202610" `
    -KnownIssueIds @("202610") `
    -SelectionFile $selection
  $newLegacy = Get-Content -LiteralPath $selection -Raw | ConvertFrom-Json
  if ((@($newLegacy.selectedIssueIds) -join ',') -ne "202508") {
    throw "New legacy scope did not select only missing old issues."
  }
  if ($global:qijiReviewScopeCommands.Count -ne 1 -or $global:qijiReviewScopeCommands[0] -notmatch 'sync mock:issues/202508') {
    throw "New legacy scope synced unexpected issue folders."
  }

  $global:qijiReviewScopeCommands.Clear()
  $selection = Join-Path $root "issue.json"
  & (Join-Path $PSScriptRoot "sync_google_drive.ps1") `
    -Remote "mock:issues" `
    -Destination (Join-Path $root "issue") `
    -Scope "issue" `
    -SpecificIssueId "202610" `
    -SelectionFile $selection
  $issue = Get-Content -LiteralPath $selection -Raw | ConvertFrom-Json
  if ((@($issue.selectedIssueIds) -join ',') -ne "202610" -or $global:qijiReviewScopeCommands.Count -ne 1) {
    throw "Issue scope did not copy only the requested issue folder."
  }

  Write-Host "Review import scope regression passed."
} finally {
  Remove-Item function:\rclone -ErrorAction SilentlyContinue
  Remove-Variable qijiReviewScopeCommands -Scope Global -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
