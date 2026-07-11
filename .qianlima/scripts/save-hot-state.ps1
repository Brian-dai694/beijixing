param(
  [Parameter(Mandatory)]
  [string]$SessionId,
  [Parameter(Mandatory)]
  [string]$Route,
  [ValidateSet('L0', 'L1', 'L2', 'L3', 'L4')]
  [string]$ServiceLevel,
  [ValidateSet('A', 'B', 'C')]
  [string]$EvidenceGrade = 'C',
  [string]$Freshness = 'unknown',
  [string[]]$SourceRef = @(),
  [string[]]$PendingCheck = @(),
  [string]$LastActionSummary = '',
  [string]$ObjectId = '',
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

if ($SessionId -match '[\\/:*?"<>|]' -or $SessionId.Length -gt 80) {
  throw 'SessionId must be a short file-safe identifier.'
}
if ($ObjectId -and ($ObjectId -match '[\\/:*?"<>|]' -or $ObjectId.Length -gt 80)) {
  throw 'ObjectId must be a short file-safe identifier.'
}

$forbidden = '(?i)(api[_-]?key|token|cookie|password|private[_-]?url|account[_-]?id|customer)'
foreach ($value in @($SourceRef + $PendingCheck + @($LastActionSummary))) {
  if ($value -match $forbidden) {
    throw 'Hot state cannot store sensitive fields or values.'
  }
}

$workingPath = Join-Path $Root 'working'
if (-not (Test-Path -LiteralPath $workingPath -PathType Container)) {
  New-Item -ItemType Directory -Path $workingPath -Force | Out-Null
}

$state = [PSCustomObject]@{
  schema_version = 1
  updated_at = (Get-Date).ToString('o')
  session_id = $SessionId
  object_id = $ObjectId
  selected_route = $Route
  service_level = $ServiceLevel
  evidence_grade = $EvidenceGrade
  freshness = $Freshness
  source_refs = @($SourceRef)
  pending_checks = @($PendingCheck)
  last_action_summary = $LastActionSummary
}

$fileName = if ($ObjectId) { "task-memory-$ObjectId.json" } else { "session-state-$SessionId.json" }
$outputPath = Join-Path $workingPath $fileName
$state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outputPath -Encoding UTF8
Write-Host "Hot state saved: $outputPath"
