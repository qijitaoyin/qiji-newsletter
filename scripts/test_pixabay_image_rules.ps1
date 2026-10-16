$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "pixabay_image_rules.ps1")

$good = [pscustomobject]@{ id = 1; type = "photo"; tags = "nature, landscape, mountain, lake"; imageWidth = 1920; imageHeight = 1080 }
$person = [pscustomobject]@{ id = 2; type = "photo"; tags = "nature, landscape, person, silhouette"; imageWidth = 1920; imageHeight = 1080 }
$fantasy = [pscustomobject]@{ id = 3; type = "photo"; tags = "nature, fantasy, moon, digital art"; imageWidth = 1920; imageHeight = 1080 }
$square = [pscustomobject]@{ id = 4; type = "photo"; tags = "nature, landscape, forest"; imageWidth = 1280; imageHeight = 1280 }
$illustration = [pscustomobject]@{ id = 5; type = "illustration"; tags = "nature, landscape, forest"; imageWidth = 1920; imageHeight = 1080 }

if (-not (Test-NaturalLandscapePixabayCandidate $good)) { throw "Real horizontal landscape should pass." }
if (Test-NaturalLandscapePixabayCandidate $person) { throw "People/silhouette image should be rejected." }
if (Test-NaturalLandscapePixabayCandidate $fantasy) { throw "Fantasy/digital-art image should be rejected." }
if (Test-NaturalLandscapePixabayCandidate $square) { throw "Square image should be rejected." }
if (Test-NaturalLandscapePixabayCandidate $illustration) { throw "Illustration should be rejected." }
if ((Get-PixabayCandidateQualityScore $good) -le 0) { throw "Natural landscape should receive a positive score." }

Write-Host "Pixabay image rule regression test passed."
