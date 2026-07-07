param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$sourceFolderName = [string]::Concat([char]0x5404, [char]0x671F, [char]0x96FB, [char]0x5B50, [char]0x5831)
$sourceRoot = Join-Path $Root $sourceFolderName
if (-not (Test-Path -LiteralPath $sourceRoot)) {
  throw "Source folder not found: $sourceRoot"
}

$resolvedRoot = (Resolve-Path -LiteralPath $sourceRoot).Path
$candidates = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force -File |
  Where-Object {
    $_.Length -eq 0 -or
    $_.Name -like "._*" -or
    $_.Name -like "~$*" -or
    $_.Name -eq ".DS_Store" -or
    $_.Name -like "*.tmp" -or
    $_.Name -like "*.download"
  }

$items = @($candidates | Where-Object {
  $fullName = $_.FullName
  $fullName.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)
})

Write-Host "Cleanup target root: $resolvedRoot"
Write-Host "Cleanup candidates: $($items.Count)"

foreach ($item in $items) {
  if ($DryRun) {
    Write-Host "[dry-run] remove $($item.FullName)"
  } else {
    Remove-Item -LiteralPath $item.FullName -Force
    Write-Host "removed $($item.FullName)"
  }
}
