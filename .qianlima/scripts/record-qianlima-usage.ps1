<#
.SYNOPSIS
    Appends one versioned usage record to the canonical JSONL ledger.
.DESCRIPTION
    Records measured or estimated model usage, tokenizer provenance, latency,
    effective task cost, and billing reconciliation in
    .qianlima/usage-ledger/runs.jsonl. The ledger is append-only. Currency is
    mandatory for all cost values; this script never converts or totals money
    across currencies.
.PARAMETER LedgerPath
    Optional ledger path for isolated tests or a private workspace. Defaults to
    .qianlima/usage-ledger/runs.jsonl under the project root.
.EXAMPLE
    ./record-qianlima-usage.ps1 -WorkflowId keyword_diagnosis -InputTokens 1200 -OutputTokens 340 -ToolCalls 3
#>
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')]
  [string]$WorkflowId,

  [string]$RunId = '',
  [string]$TaskName = '',
  [string]$Provider = 'local',
  [string]$Model = 'local-script',
  [string]$WorkloadType = 'unknown',
  [string]$TokenizerId = 'unknown',
  [string]$TokenizerVersion = 'unknown',
  [ValidateSet('provider_usage', 'official_counter', 'local_encoder', 'estimate', 'unknown')]
  [string]$TokenMeasurementMethod = 'unknown',
  [string]$TokenMeasurementReference = '',
  [ValidateRange(0, [double]::MaxValue)]
  [double]$InputTokens = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$OutputTokens = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$CacheHitTokens = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$ReasoningTokens = 0,
  [Nullable[double]]$EstimatedInputTokens = $null,
  [Nullable[double]]$EstimatedOutputTokens = $null,
  [ValidateRange(0, [int]::MaxValue)]
  [int]$ToolCalls = 0,
  [ValidateRange(0, [int]::MaxValue)]
  [int]$RowsRead = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$DurationSeconds = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$StartupMs = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$RoutingMs = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$ContextLoadMs = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$ToolMs = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$ModelMs = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$FirstUsefulOutputMs = 0,
  [Alias('EstimatedCostUsd')]
  [ValidateRange(0, [double]::MaxValue)]
  [double]$EstimatedCost = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$ToolCost = 0,
  [ValidatePattern('^[A-Za-z]{3}$')]
  [string]$Currency = 'USD',
  [string]$ToolCostCurrency = '',
  [Nullable[double]]$BilledCost = $null,
  [string]$BilledCostCurrency = '',
  [ValidateRange(0, [double]::MaxValue)]
  [double]$BillingTolerancePct = 1,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$BaselineCost = 0,
  [ValidateRange(0, [double]::MaxValue)]
  [double]$CostLimit = 0,
  [string]$CostStatus = 'estimate',
  [string]$SavingsSource = 'unknown',
  [string]$ContinueOrStop = 'continue',
  [ValidateRange(-[double]::MaxValue, [double]::MaxValue)]
  [double]$EstimatedSavings = 0,
  [ValidateRange(-[double]::MaxValue, [double]::MaxValue)]
  [double]$SavingsRatePct = 0,
  [ValidateRange(0, [int]::MaxValue)]
  [int]$OutcomeUnits = 0,
  [string]$OutcomeUnit = '',
  [ValidateSet('completed', 'partial', 'failed', 'cancelled')]
  [string]$Status = 'completed',
  [string]$Notes = '',
  [string]$LedgerPath = '',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

if ($CacheHitTokens -gt $InputTokens) { throw 'CacheHitTokens cannot exceed InputTokens.' }
if ($ReasoningTokens -gt $OutputTokens) { throw 'ReasoningTokens cannot exceed OutputTokens.' }
if (($null -ne $EstimatedInputTokens) -and $EstimatedInputTokens -lt 0) { throw 'EstimatedInputTokens must be zero or greater.' }
if (($null -ne $EstimatedOutputTokens) -and $EstimatedOutputTokens -lt 0) { throw 'EstimatedOutputTokens must be zero or greater.' }
if ($ToolCost -gt $EstimatedCost) { throw 'ToolCost cannot exceed EstimatedCost because EstimatedCost is the total effective task cost.' }

$currencyCode = $Currency.ToUpperInvariant()
$toolCurrencyCode = if ([string]::IsNullOrWhiteSpace($ToolCostCurrency)) { $currencyCode } else { $ToolCostCurrency.ToUpperInvariant() }
if ($toolCurrencyCode -notmatch '^[A-Z]{3}$') { throw 'ToolCostCurrency must be a three-letter currency code.' }
if ($ToolCost -gt 0 -and $toolCurrencyCode -ne $currencyCode) {
  throw 'ToolCostCurrency must match Currency. Record an FX conversion as a separate, evidenced financial operation before combining costs.'
}
$billedCurrencyCode = if ([string]::IsNullOrWhiteSpace($BilledCostCurrency)) { $currencyCode } else { $BilledCostCurrency.ToUpperInvariant() }
if ($billedCurrencyCode -notmatch '^[A-Z]{3}$') { throw 'BilledCostCurrency must be a three-letter currency code.' }
if (($null -ne $BilledCost) -and $billedCurrencyCode -ne $currencyCode) {
  throw 'BilledCostCurrency must match Currency. Billing reconciliation does not perform implicit FX conversion.'
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($LedgerPath)) {
  $ledgerDirectory = Join-Path $projectRoot '.qianlima\usage-ledger'
  $LedgerPath = Join-Path $ledgerDirectory 'runs.jsonl'
} else {
  $ledgerDirectory = Split-Path -Parent $LedgerPath
}
if ([string]::IsNullOrWhiteSpace($ledgerDirectory)) { throw 'LedgerPath must include a parent directory.' }
if (-not (Test-Path -LiteralPath $ledgerDirectory -PathType Container)) {
  New-Item -ItemType Directory -Path $ledgerDirectory -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
  $RunId = "$WorkflowId-$((Get-Date).ToString('yyyyMMdd-HHmmss-fff'))"
}
if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) {
  $duplicate = Get-Content -LiteralPath $LedgerPath -Encoding UTF8 |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object {
      try { $_ | ConvertFrom-Json } catch { $null }
    } |
    Where-Object { $null -ne $_ -and $_.run_id -eq $RunId } |
    Select-Object -First 1
  if ($null -ne $duplicate) { throw "Usage ledger already contains run id: $RunId" }
}

$modelCost = $EstimatedCost - $ToolCost
$estimatedTotalTokens = if (($null -ne $EstimatedInputTokens) -and ($null -ne $EstimatedOutputTokens)) { $EstimatedInputTokens + $EstimatedOutputTokens } else { $null }
$actualTotalTokens = $InputTokens + $OutputTokens
$inputTokenDelta = if ($null -ne $EstimatedInputTokens) { $InputTokens - $EstimatedInputTokens } else { $null }
$outputTokenDelta = if ($null -ne $EstimatedOutputTokens) { $OutputTokens - $EstimatedOutputTokens } else { $null }
$totalTokenDelta = if ($null -ne $estimatedTotalTokens) { $actualTotalTokens - $estimatedTotalTokens } else { $null }
$inputTokenDeltaPct = if (($null -ne $EstimatedInputTokens) -and ($EstimatedInputTokens -gt 0)) { [math]::Round(($inputTokenDelta / $EstimatedInputTokens) * 100, 2) } else { $null }
$totalTokenDeltaPct = if (($null -ne $estimatedTotalTokens) -and ($estimatedTotalTokens -gt 0)) { [math]::Round(($totalTokenDelta / $estimatedTotalTokens) * 100, 2) } else { $null }
$billingStatus = 'not_available'
$costDelta = $null
$costDeltaPct = $null
if ($null -ne $BilledCost) {
  if ($EstimatedCost -le 0) {
    $billingStatus = 'estimate_missing'
  } else {
    $costDelta = $BilledCost - $EstimatedCost
    $costDeltaPct = [math]::Round(($costDelta / $EstimatedCost) * 100, 2)
    $billingStatus = if ([math]::Abs($costDeltaPct) -le $BillingTolerancePct) { 'within_tolerance' } else { 'variance_detected' }
  }
}

$record = [ordered]@{
  schema_version = 2
  run_id = $RunId
  workflow_id = $WorkflowId
  task_name = $TaskName
  provider = $Provider
  model = $Model
  workload_type = $WorkloadType
  tokenizer_id = $TokenizerId
  tokenizer_version = $TokenizerVersion
  token_measurement_method = $TokenMeasurementMethod
  token_measurement_reference = $TokenMeasurementReference
  input_tokens = $InputTokens
  output_tokens = $OutputTokens
  cache_hit_tokens = $CacheHitTokens
  reasoning_tokens = $ReasoningTokens
  estimated_input_tokens = $EstimatedInputTokens
  estimated_output_tokens = $EstimatedOutputTokens
  actual_total_tokens = $actualTotalTokens
  estimated_total_tokens = $estimatedTotalTokens
  input_token_delta = $inputTokenDelta
  output_token_delta = $outputTokenDelta
  total_token_delta = $totalTokenDelta
  input_token_delta_pct = $inputTokenDeltaPct
  total_token_delta_pct = $totalTokenDeltaPct
  tool_calls = $ToolCalls
  rows_read = $RowsRead
  duration_seconds = $DurationSeconds
  startup_ms = $StartupMs
  routing_ms = $RoutingMs
  context_load_ms = $ContextLoadMs
  tool_ms = $ToolMs
  model_ms = $ModelMs
  first_useful_output_ms = $FirstUsefulOutputMs
  currency = $currencyCode
  estimated_cost = $EstimatedCost
  model_cost = $modelCost
  tool_cost = $ToolCost
  tool_cost_currency = $toolCurrencyCode
  billed_cost = $BilledCost
  billed_cost_currency = if ($null -ne $BilledCost) { $billedCurrencyCode } else { $null }
  billing_status = $billingStatus
  billing_cost_delta = $costDelta
  billing_cost_delta_pct = $costDeltaPct
  billing_tolerance_pct = $BillingTolerancePct
  baseline_cost = $BaselineCost
  cost_limit = $CostLimit
  cost_status = $CostStatus
  savings_source = $SavingsSource
  continue_or_stop = $ContinueOrStop
  estimated_savings = $EstimatedSavings
  estimated_savings_rate_pct = $SavingsRatePct
  outcome_units = $OutcomeUnits
  outcome_unit = $OutcomeUnit
  status = $Status
  notes = $Notes
  recorded_at = (Get-Date).ToUniversalTime().ToString('o')
}

# One JSON object per line keeps the private ledger append-only and stream-friendly.
$json = $record | ConvertTo-Json -Compress -Depth 5
[System.IO.File]::AppendAllText($LedgerPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

if ($PassThru) {
  [PSCustomObject]@{
    LedgerPath = $LedgerPath
    RunId = $RunId
    Record = [PSCustomObject]$record
  }
} else {
  Write-Host "Usage ledger appended: $LedgerPath"
  Write-Host "Run ID: $RunId"
}
