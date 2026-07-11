param(
  [Parameter(Mandatory)]
  [string]$RequestId,
  [Parameter(Mandatory)]
  [string]$Route,
  [ValidateSet('quick', 'evidence', 'execute')]
  [string]$ReliabilityMode = 'quick',
  [ValidateSet('generic', 'replenishment', 'advertising_diagnosis', 'keyword_diagnosis', 'profit_check')]
  [string]$DecisionType = 'generic',
  [int]$TimeBudgetSeconds = 0,
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
if ($RequestId -match '[\\/:*?"<>|]' -or $RequestId.Length -gt 80) {
  throw 'RequestId must be a short file-safe identifier.'
}

$defaultBudgets = @{ quick = 3; evidence = 30; execute = 90 }
if ($TimeBudgetSeconds -le 0) { $TimeBudgetSeconds = $defaultBudgets[$ReliabilityMode] }

$minimumEvidence = @{
  generic = @()
  replenishment = @('inventory_on_hand', 'sales_7d_or_30d', 'inbound_qty', 'lead_time')
  advertising_diagnosis = @('spend', 'sales', 'acos_or_roas', 'date_range')
  keyword_diagnosis = @('keyword', 'current_rank', 'prior_rank_or_baseline', 'source_timestamp')
  profit_check = @('price', 'fees', 'ad_rate', 'date_or_assumption_source')
}

$workingPath = Join-Path $Root 'working'
if (-not (Test-Path -LiteralPath $workingPath -PathType Container)) {
  New-Item -ItemType Directory -Path $workingPath -Force | Out-Null
}

$now = Get-Date
$contract = [PSCustomObject]@{
  schema_version = 1
  request_id = $RequestId
  route = $Route
  reliability_mode = $ReliabilityMode
  decision_type = $DecisionType
  time_budget_seconds = $TimeBudgetSeconds
  started_at = $now.ToString('o')
  deadline_at = $now.AddSeconds($TimeBudgetSeconds).ToString('o')
  state = 'classify'
  control = 'continue'
  minimum_evidence = [object[]]$minimumEvidence[$DecisionType]
  pending_checks = @()
  freeze_action = 'conclusion_only'
}

$outputPath = Join-Path $workingPath "task-contract-$RequestId.json"
$contract | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outputPath -Encoding UTF8
Write-Host "Task contract created: $outputPath"
