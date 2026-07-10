param(
  [string]$Remote = $env:GOOGLE_DRIVE_REMOTE,
  [string]$Destination = "",
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
  "--fast-list",
  "--checkers", "32",
  "--transfers", "16",
  "--drive-chunk-size", "64M"
)

foreach ($folder in $ignoredFolders) {
  $arguments += @("--exclude", "$folder/**")
  $arguments += @("--exclude", "**/$folder/**")
}

$arguments += "--verbose"

if ($DryRun) {
  $arguments += "--dry-run"
}

Write-Host "Syncing Google Drive source..."
Write-Host "Remote: $Remote"
Write-Host "Destination: $Destination"
Write-Host "Ignored staging folders: $($ignoredFolders -join ', ')"

& rclone @arguments
if ($LASTEXITCODE -ne 0) {
  throw "rclone sync failed with exit code $LASTEXITCODE"
}
