param(
  [string]$Remote = $env:GOOGLE_DRIVE_REMOTE,
  [string]$Destination = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "各期電子報"),
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Remote)) {
  throw "Missing Google Drive remote. Set GOOGLE_DRIVE_REMOTE, for example qiji-drive:newsletter/各期電子報"
}

$rclone = Get-Command rclone -ErrorAction SilentlyContinue
if (-not $rclone) {
  throw "rclone is required. Install rclone locally or provide it in GitHub Actions before running this script."
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

$arguments = @(
  "sync",
  $Remote,
  $Destination,
  "--create-empty-src-dirs",
  "--exclude", ".DS_Store",
  "--exclude", "._*",
  "--exclude", "~$*",
  "--exclude", "*.tmp",
  "--exclude", "*.download",
  "--verbose"
)

if ($DryRun) {
  $arguments += "--dry-run"
}

Write-Host "Syncing Google Drive source..."
Write-Host "Remote: $Remote"
Write-Host "Destination: $Destination"

& rclone @arguments
if ($LASTEXITCODE -ne 0) {
  throw "rclone sync failed with exit code $LASTEXITCODE"
}
