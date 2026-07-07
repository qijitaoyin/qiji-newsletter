param(
  [string]$PublishFile = "review-publish.json",
  [string]$OverridesFile = "src/data/editorialOverrides.json"
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

if (-not (Test-Path -LiteralPath $PublishFile)) {
  throw "找不到發布核准檔：$PublishFile。請先從 /review/ 下載 review-publish.json 並放到專案根目錄。"
}

$publish = Read-JsonFile $PublishFile '{ "metadataOverrides": { "quotes": {}, "tags": {} } }'
$overrides = Read-JsonFile $OverridesFile '{ "quotes": {}, "tags": {} }'

if ($publish.status -eq "has-open-tasks") {
  Write-Warning "發布核准檔仍有未完成待辦。若只是測試可繼續；正式發布前請先確認所有待辦完成。"
}

if (-not $overrides.PSObject.Properties["quotes"]) {
  $overrides | Add-Member -MemberType NoteProperty -Name quotes -Value ([pscustomobject]@{})
}
if (-not $overrides.PSObject.Properties["tags"]) {
  $overrides | Add-Member -MemberType NoteProperty -Name tags -Value ([pscustomobject]@{})
}

$quoteCount = 0
$tagCount = 0
$quotes = $publish.metadataOverrides.quotes
if ($quotes) {
  foreach ($prop in $quotes.PSObject.Properties) {
    $slug = $prop.Name
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
    $slug = $prop.Name
    $value = @($prop.Value) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
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

$json = $overrides | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText((Join-Path (Get-Location) $OverridesFile), $json, [System.Text.UTF8Encoding]::new($false))

Write-Host "已套用發布核准資料：$quoteCount 筆金句、$tagCount 筆標籤。"
Write-Host "已更新：$OverridesFile"
