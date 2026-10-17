function Resolve-ReviewImportRequest {
  param(
    [string]$EventName = "",
    [string]$RequestedImportTarget = "",
    [string]$ReviewPublishJson = ""
  )

  $scope = "all"
  $specificIssueId = $RequestedImportTarget
  $aiIssueId = $RequestedImportTarget

  if ($EventName -eq "workflow_dispatch") {
    if (-not [string]::IsNullOrWhiteSpace($ReviewPublishJson)) {
      try {
        $publishRequest = $ReviewPublishJson | ConvertFrom-Json
      } catch {
        throw "Review publish payload is not valid JSON."
      }

      $publishIssueId = [string]$publishRequest.issueId
      if ($publishIssueId -notmatch '^20\d{4}$') {
        throw "Review publish payload must include a six-digit issueId."
      }

      $scope = "issue"
      $specificIssueId = $publishIssueId
      $aiIssueId = $publishIssueId
    } elseif ($RequestedImportTarget -eq "latest") {
      $scope = "latest"
    } elseif ($RequestedImportTarget -eq "new-legacy") {
      $scope = "new-legacy"
    } elseif ($RequestedImportTarget -eq "published") {
      $scope = "published"
    } elseif ($RequestedImportTarget -match '^20\d{4}$') {
      $scope = "issue"
    }
  }

  [pscustomobject]@{
    Scope = $scope
    SpecificIssueId = $specificIssueId
    AiIssueId = $aiIssueId
  }
}
