param(
  [Parameter(Mandatory)]
  [string]$Route,
  [Parameter(Mandatory)]
  [string[]]$Fact,
  [string[]]$Anomaly = @(),
  [string[]]$SourceRef = @(),
  [ValidateRange(60, 86400)]
  [int]$TtlSeconds = 900,
  [ValidateSet('passed', 'failed')]
  [string]$QualityStatus = 'passed',
  [string]$Root = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
if ($Route -match '[\\/:*?"<>|]' -or $Route.Length -gt 80) {
  throw 'Route must be a short file-safe identifier.'
}

$forbidden = '(?i)(api[_-]?key|token|cookie|password|private[_-]?url|account[_-]?id|customer|email|phone)'
foreach ($value in @($Fact + $Anomaly + $SourceRef)) {
  if ($value -match $forbidden) {
    throw 'Snapshot cannot store sensitive fields or values.'
  }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $snapshotDir = Join-Path (Join-Path $Root 'working') 'snapshots'
  if (-not (Test-Path -LiteralPath $snapshotDir -PathType Container)) {
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
  }
  $OutputPath = Join-Path $snapshotDir "snapshot-$Route.json"
}

$snapshot = [PSCustomObject]@{
  schema_version = 1
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  ttl_seconds = $TtlSeconds
  route = $Route
  quality_status = $QualityStatus
  evidence_grade = 'B'
  facts = [object[]]$Fact
  anomalies = [object[]]$Anomaly
  source_refs = [object[]]$SourceRef
}
$snapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "Operational snapshot saved: $OutputPath"
