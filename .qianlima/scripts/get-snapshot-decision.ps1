param(
  [Parameter(Mandatory)]
  [string]$SnapshotPath,
  [int]$SWRSeconds = 3600,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) {
  throw "Snapshot not found: $SnapshotPath"
}

$snapshot = Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($snapshot.quality_status -ne 'passed') {
  $decision = 'live_evidence_required'
  $grade = 'C'
  $reason = 'Snapshot quality status is not passed.'
} else {
  $generatedAt = [datetimeoffset]::Parse($snapshot.generated_at)
  $ageSeconds = [math]::Max(0, [math]::Round(([datetimeoffset]::Now - $generatedAt).TotalSeconds))
  $ttl = if ($snapshot.ttl_seconds -gt 0) { [int]$snapshot.ttl_seconds } else { 900 }
  if ($ageSeconds -le $ttl) {
    $decision = 'serve_snapshot_and_refresh'
    $grade = 'B'
    $reason = 'Snapshot is within its fresh TTL.'
  } elseif ($ageSeconds -le ($ttl + $SWRSeconds)) {
    $decision = 'serve_stale_snapshot_and_refresh_before_final'
    $grade = 'C'
    $reason = 'Snapshot is in the stale-while-revalidate window.'
  } else {
    $decision = 'live_evidence_required'
    $grade = 'C'
    $reason = 'Snapshot is beyond its stale-while-revalidate window.'
  }
}

$result = [PSCustomObject]@{
  route = $snapshot.route
  decision = $decision
  evidence_grade = $grade
  reason = $reason
  facts = [object[]]@($snapshot.facts)
  anomalies = [object[]]@($snapshot.anomalies)
  source_refs = [object[]]@($snapshot.source_refs)
}
if ($Json) { $result | ConvertTo-Json -Depth 5 } else { $result | Format-List }
