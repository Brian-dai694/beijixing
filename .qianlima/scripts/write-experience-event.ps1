param(
  [Parameter(Mandatory)]
  [string]$RunId,
  [ValidateSet('first_delivery', 'final_delivery', 'tool_call', 'snapshot_decision', 'task_frozen', 'task_cancelled')]
  [string]$EventType,
  [ValidateSet('startup', 'routing', 'snapshot', 'tool', 'aggregation', 'model', 'final_delivery')]
  [string]$Component,
  [ValidateRange(0, 3600000)]
  [int]$LatencyMs,
  [ValidateSet('unknown', 'yes', 'no')]
  [string]$EvidenceComplete = 'unknown',
  [ValidateSet('unknown', 'yes', 'no')]
  [string]$UserAdopted = 'unknown',
  [ValidateSet('unknown', 'yes', 'no')]
  [string]$SnapshotHit = 'unknown',
  [ValidateSet('primary', 'fallback', 'avoid', 'unknown')]
  [string]$ToolHealthTier = 'unknown',
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

function ConvertTo-NullableBoolean([string]$Value) {
  switch ($Value) {
    'yes' { return $true }
    'no' { return $false }
    default { return $null }
  }
}

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
if ($RunId -match '[\\/:*?"<>|]' -or $RunId.Length -gt 80) {
  throw 'RunId must be a short file-safe identifier.'
}

$logPath = Join-Path (Join-Path $Root 'logs') 'experience-events.jsonl'
$logDirectory = Split-Path -Parent $logPath
if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
  New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

$event = [PSCustomObject]@{
  schema_version = 1
  run_id = $RunId
  event_type = $EventType
  component = $Component
  latency_ms = $LatencyMs
  evidence_complete = ConvertTo-NullableBoolean $EvidenceComplete
  user_adopted = ConvertTo-NullableBoolean $UserAdopted
  snapshot_hit = ConvertTo-NullableBoolean $SnapshotHit
  tool_health_tier = $ToolHealthTier
  recorded_at = (Get-Date).ToString('o')
}

($event | ConvertTo-Json -Compress) | Add-Content -LiteralPath $logPath -Encoding UTF8
Write-Host "Experience event recorded: $EventType/$Component"
