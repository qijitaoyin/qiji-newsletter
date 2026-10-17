param(
  [string]$Remote = $env:GOOGLE_DRIVE_REMOTE,
  [string]$Destination = "",
  [ValidateSet("all", "latest", "new-legacy", "published", "issue")]
  [string]$Scope = "all",
  [string]$PublicLatestIssueId = "",
  [string]$SpecificIssueId = "",
  [string[]]$KnownIssueIds = @(),
  [string]$SelectionFile = "",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$sourceFolderName = -join @(
  [char]0x5404, # ge
  [char]0x671F, # qi
  [char]0x96FB, # dian
  [char]0x5B50, # zi
  [char]0x5831  # bao
)

if ([string]::IsNullOrWhiteSpace($Destination)) {
  $Destination = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path $sourceFolderName
}

if ([string]::IsNullOrWhiteSpace($Remote)) {
  throw "Missing Google Drive remote. Set GOOGLE_DRIVE_REMOTE, for example qiji-drive:$sourceFolderName"
}

$rclone = Get-Command rclone -ErrorAction SilentlyContinue
if (-not $rclone) {
  throw "rclone is required. Install rclone locally or provide it in GitHub Actions before running this script."
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

$remoteIssueFolders = @(
  & rclone lsf $Remote --dirs-only --max-depth 1 |
    ForEach-Object { ([string]$_).Trim().TrimEnd('/') } |
    Where-Object { $_ -match '^20\d{4}$' } |
    Sort-Object -Unique
)
if ($LASTEXITCODE -ne 0) {
  throw "rclone could not list Google Drive issue folders (exit code $LASTEXITCODE)"
}

$selectedIssueIds = switch ($Scope) {
  "latest" {
    @($remoteIssueFolders | Sort-Object -Descending | Select-Object -First 1)
  }
  "published" {
    if ([string]::IsNullOrWhiteSpace($PublicLatestIssueId)) {
      throw "PublicLatestIssueId is required for the published scope."
    }
    @($remoteIssueFolders | Where-Object { $_ -le $PublicLatestIssueId } | Sort-Object)
  }
  "new-legacy" {
    if ([string]::IsNullOrWhiteSpace($PublicLatestIssueId)) {
      throw "PublicLatestIssueId is required for the new-legacy scope."
    }
    $known = @($KnownIssueIds | Where-Object { $_ -match '^20\d{4}$' } | Sort-Object -Unique)
    @(
      $remoteIssueFolders |
        Where-Object { $_ -le $PublicLatestIssueId -and $_ -notin $known } |
        Sort-Object
    )
  }
  "issue" {
    if ([string]::IsNullOrWhiteSpace($SpecificIssueId) -or $SpecificIssueId -notmatch '^20\d{4}$') {
      throw "SpecificIssueId is required for the issue scope."
    }
    if ($SpecificIssueId -notin $remoteIssueFolders) {
      throw "Issue folder $SpecificIssueId was not found in Google Drive."
    }
    @($SpecificIssueId)
  }
  default { @($remoteIssueFolders) }
}

if ($SelectionFile) {
  $selectionParent = Split-Path -Parent $SelectionFile
  if ($selectionParent) { New-Item -ItemType Directory -Force -Path $selectionParent | Out-Null }
  [ordered]@{
    scope = $Scope
    publicLatestIssueId = $PublicLatestIssueId
    specificIssueId = $SpecificIssueId
    knownIssueIds = @($KnownIssueIds | Sort-Object -Unique)
    availableIssueIds = @($remoteIssueFolders)
    selectedIssueIds = @($selectedIssueIds)
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $SelectionFile -Encoding UTF8
}

$ignoredFolders = @(
  "draft",
  "drafts",
  "staging",
  (-join @([char]0x6574, [char]0x7406, [char]0x4E2D)), # zheng li zhong
  (-join @([char]0x5F85, [char]0x6574, [char]0x7406)), # dai zheng li
  (-join @([char]0x66AB, [char]0x5B58)), # zan cun
  (-join @([char]0x66AB, [char]0x4E0D, [char]0x4E0A, [char]0x67B6)), # zan bu shang jia
  (-join @([char]0x4E0D, [char]0x4E0A, [char]0x67B6)), # bu shang jia
  (-join @([char]0x672A, [char]0x4E0A, [char]0x67B6)), # wei shang jia
  (-join @([char]0x6821, [char]0x7A3F, [char]0x4E2D)) # jiao gao zhong
)

$commonArguments = @(
  "--create-empty-src-dirs",
  "--exclude", ".DS_Store",
  "--exclude", "._*",
  "--exclude", "~$*",
  "--exclude", "*.tmp",
  "--exclude", "*.download",
  "--fast-list",
  "--checkers", "32",
  "--transfers", "16",
  "--drive-chunk-size", "64M"
)

foreach ($folder in $ignoredFolders) {
  $commonArguments += @("--exclude", "$folder/**")
  $commonArguments += @("--exclude", "**/$folder/**")
}

$commonArguments += "--verbose"

if ($DryRun) {
  $commonArguments += "--dry-run"
}

Write-Host "Syncing Google Drive source..."
Write-Host "Remote: $Remote"
Write-Host "Destination: $Destination"
Write-Host "Scope: $Scope"
Write-Host "Selected issue folders: $($selectedIssueIds -join ', ')"
Write-Host "Ignored staging folders: $($ignoredFolders -join ', ')"

if ($Scope -eq "all") {
  & rclone sync $Remote $Destination @commonArguments
  if ($LASTEXITCODE -ne 0) {
    throw "rclone sync failed with exit code $LASTEXITCODE"
  }
} else {
  foreach ($issueId in $selectedIssueIds) {
    $issueDestination = Join-Path $Destination $issueId
    New-Item -ItemType Directory -Force -Path $issueDestination | Out-Null
    & rclone sync "$Remote/$issueId" $issueDestination @commonArguments
    if ($LASTEXITCODE -ne 0) {
      throw "rclone sync failed for issue $issueId with exit code $LASTEXITCODE"
    }
  }
}
