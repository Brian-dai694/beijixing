<#
.SYNOPSIS
    Creates a human-readable YAML record and appends its canonical JSONL ledger entry.
.DESCRIPTION
    Writes a per-run usage/cost evidence file under usage-ledger and appends the
    same run to the canonical runs.jsonl ledger. Validates that
    token and cost inputs are non-negative, optionally prices the run from the
    model cost catalog (-AutoPrice), and computes savings and savings rate from
    the baseline. EstimatedCost is the total effective task cost; ToolCost is
    an optional breakdown that must not exceed it. Flags cost_status as over_limit or over_baseline_guard and
    may switch continue_or_stop to needs_confirmation.
.PARAMETER RunId
    Run identifier; sanitized to form the YAML file name.
.PARAMETER AutoPrice
    Price the run from get-model-cost.ps1 instead of using manual estimates.
.PARAMETER CostLimit
    Cost ceiling; exceeding it marks the run over_limit.
.PARAMETER Force
    Overwrite an existing YAML evidence file only when no canonical JSONL entry
    exists for the run id. Canonical ledger entries are always append-only.
.EXAMPLE
    ./new-usage-record.ps1 -RunId 2026-07-13_run_001 -ModelProvider openai -ModelName gpt-x -InputTokens 1000 -OutputTokens 500 -AutoPrice
#>
param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$RunId = "$(Get-Date -Format 'yyyy-MM-dd')_manual_001",
  [string]$TaskName = 'replace_me',
  [string]$WorkflowId = 'replace_me',
  [string]$ModelProvider = 'unknown',
  [string]$ModelName = 'unknown',
  [string]$OutputFile = 'replace_me',
  [int]$InputTokens = 0,
  [int]$OutputTokens = 0,
  [int]$CachedInputTokens = 0,
  [int]$ReasoningTokens = 0,
  [Nullable[int]]$EstimatedInputTokens = $null,
  [Nullable[int]]$EstimatedOutputTokens = $null,
  [string]$TokenizerId = 'unknown',
  [string]$TokenizerVersion = 'unknown',
  [string]$WorkloadType = 'unknown',
  [ValidateSet('provider_usage', 'official_counter', 'local_encoder', 'estimate', 'unknown')]
  [string]$TokenMeasurementMethod = 'unknown',
  [string]$TokenMeasurementReference = '',
  [Nullable[decimal]]$BilledCost = $null,
  [string]$BilledCostCurrency = '',
  [decimal]$BillingTolerancePct = 1,
  [decimal]$ToolCost = 0,
  [string]$ToolCostCurrency = '',
  [decimal]$EstimatedCost = 0,
  [decimal]$BaselineCost = 0,
  [decimal]$EstimatedSavings = 0,
  [decimal]$SavingsRatePct = 0,
  [decimal]$CostLimit = 0,
  [ValidatePattern('^[A-Za-z]{3}$')]
  [string]$Currency = 'USD',
  [switch]$AutoPrice,
  [string]$CostStatus = 'estimate',
  [string]$SavingsSource = 'unknown',
  [string]$ContinueOrStop = 'continue',
  [switch]$TaskSuccess,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

foreach ($value in @($InputTokens, $OutputTokens, $CachedInputTokens, $ReasoningTokens, $ToolCost, $EstimatedCost, $BaselineCost, $CostLimit, $BillingTolerancePct)) {
  if ($value -lt 0) {
    throw 'Token counts, cost values, and BillingTolerancePct must be zero or greater.'
  }
}
foreach ($value in @($EstimatedInputTokens, $EstimatedOutputTokens, $BilledCost)) {
  if (($null -ne $value) -and ($value -lt 0)) {
    throw 'Estimated token counts and BilledCost must be zero or greater when provided.'
  }
}
if ($CachedInputTokens -gt $InputTokens) {
  throw 'CachedInputTokens cannot exceed InputTokens.'
}
if ($ReasoningTokens -gt $OutputTokens) {
  throw 'ReasoningTokens cannot exceed OutputTokens.'
}

function ConvertTo-YamlScalar([string]$Value) {
  return "'" + (($Value -replace "`r?`n", ' ') -replace "'", "''") + "'"
}

$pricingCatalogVersion = ''
$pricingSourceUrl = ''
$pricingVerifiedAt = ''
$costMeteringMethod = 'manual_estimate'
if ($AutoPrice) {
  $priceScript = Join-Path $PSScriptRoot 'get-model-cost.ps1'
  $priced = & $priceScript -Provider $ModelProvider -Model $ModelName -InputTokens $InputTokens -OutputTokens $OutputTokens -CachedInputTokens $CachedInputTokens
  if ($priced.status -ne 'priced') {
    throw "No verified price for $ModelProvider/$ModelName. Source: $($priced.source_url)"
  }
  $EstimatedCost = [decimal]$priced.estimated_cost + $ToolCost
  $Currency = $priced.currency
  $pricingCatalogVersion = $priced.catalog_version
  $pricingSourceUrl = $priced.source_url
  $pricingVerifiedAt = $priced.verified_at
  $costMeteringMethod = 'official_catalog'
  $CostStatus = 'exact_catalog_rate'
}
if ($ToolCost -gt $EstimatedCost) {
  throw 'ToolCost cannot exceed EstimatedCost because EstimatedCost is the total effective task cost.'
}
$Currency = $Currency.ToUpperInvariant()
$ToolCostCurrency = if ([string]::IsNullOrWhiteSpace($ToolCostCurrency)) { $Currency } else { $ToolCostCurrency.ToUpperInvariant() }
if ($ToolCostCurrency -notmatch '^[A-Z]{3}$') { throw 'ToolCostCurrency must be a three-letter currency code.' }
if (($ToolCost -gt 0) -and ($ToolCostCurrency -ne $Currency)) {
  throw 'ToolCostCurrency must match Currency. This ledger does not perform implicit FX conversion.'
}
$BilledCostCurrency = if ([string]::IsNullOrWhiteSpace($BilledCostCurrency)) { $Currency } else { $BilledCostCurrency.ToUpperInvariant() }
if ($BilledCostCurrency -notmatch '^[A-Z]{3}$') { throw 'BilledCostCurrency must be a three-letter currency code.' }
if (($null -ne $BilledCost) -and ($BilledCostCurrency -ne $Currency)) {
  throw 'BilledCostCurrency must match Currency. This ledger does not perform implicit FX conversion.'
}

$ledgerDir = Join-Path $Root 'usage-ledger'
if (-not (Test-Path -LiteralPath $ledgerDir -PathType Container)) {
  New-Item -ItemType Directory -Path $ledgerDir | Out-Null
}

$safeRunId = $RunId -replace '[^A-Za-z0-9_.-]', '-'
$path = Join-Path $ledgerDir "$safeRunId.yaml"
if ((Test-Path -LiteralPath $path -PathType Leaf) -and (-not $Force)) {
  throw "Usage ledger already exists: $path. Re-run with -Force to overwrite."
}

# InputTokens and OutputTokens are provider totals. Cached and reasoning tokens are
# tracked as diagnostic breakdowns and must not be added again.
$totalTokens = $InputTokens + $OutputTokens
$estimatedTotalTokens = if (($null -ne $EstimatedInputTokens) -and ($null -ne $EstimatedOutputTokens)) {
  $EstimatedInputTokens + $EstimatedOutputTokens
} else {
  $null
}
$modelCost = $EstimatedCost - $ToolCost
$inputTokenDelta = if ($null -ne $EstimatedInputTokens) { $InputTokens - $EstimatedInputTokens } else { $null }
$outputTokenDelta = if ($null -ne $EstimatedOutputTokens) { $OutputTokens - $EstimatedOutputTokens } else { $null }
$totalTokenDelta = if ($null -ne $estimatedTotalTokens) { $totalTokens - $estimatedTotalTokens } else { $null }
$inputTokenDeltaPct = if (($null -ne $EstimatedInputTokens) -and ($EstimatedInputTokens -gt 0)) { [math]::Round(($inputTokenDelta / $EstimatedInputTokens) * 100, 2) } else { $null }
$totalTokenDeltaPct = if (($null -ne $estimatedTotalTokens) -and ($estimatedTotalTokens -gt 0)) { [math]::Round(($totalTokenDelta / $estimatedTotalTokens) * 100, 2) } else { $null }
$billedCostValue = if ($null -ne $BilledCost) { $BilledCost } else { 'unknown' }
$costDelta = if ($null -ne $BilledCost) { [decimal]$BilledCost - $EstimatedCost } else { $null }
$costDeltaPct = if (($null -ne $BilledCost) -and ($EstimatedCost -gt 0)) { [decimal]::Round(($costDelta / $EstimatedCost) * 100, 2) } else { $null }
$billingStatus = 'not_available'
if ($null -ne $BilledCost) {
  if ($EstimatedCost -le 0) {
    $billingStatus = 'estimate_missing'
  } elseif ([math]::Abs([double]$costDeltaPct) -le [double]$BillingTolerancePct) {
    $billingStatus = 'within_tolerance'
  } else {
    $billingStatus = 'variance_detected'
  }
}
$estimatedInputValue = if ($null -ne $EstimatedInputTokens) { $EstimatedInputTokens } else { 'unknown' }
$estimatedOutputValue = if ($null -ne $EstimatedOutputTokens) { $EstimatedOutputTokens } else { 'unknown' }
$estimatedTotalValue = if ($null -ne $estimatedTotalTokens) { $estimatedTotalTokens } else { 'unknown' }
$inputTokenDeltaValue = if ($null -ne $inputTokenDelta) { $inputTokenDelta } else { 'unknown' }
$outputTokenDeltaValue = if ($null -ne $outputTokenDelta) { $outputTokenDelta } else { 'unknown' }
$totalTokenDeltaValue = if ($null -ne $totalTokenDelta) { $totalTokenDelta } else { 'unknown' }
$inputTokenDeltaPctValue = if ($null -ne $inputTokenDeltaPct) { $inputTokenDeltaPct } else { 'unknown' }
$totalTokenDeltaPctValue = if ($null -ne $totalTokenDeltaPct) { $totalTokenDeltaPct } else { 'unknown' }
$costDeltaValue = if ($null -ne $costDelta) { $costDelta } else { 'unknown' }
$costDeltaPctValue = if ($null -ne $costDeltaPct) { $costDeltaPct } else { 'unknown' }
$computedSavings = $EstimatedSavings
if (($computedSavings -eq 0) -and ($BaselineCost -gt 0)) {
  $computedSavings = $BaselineCost - $EstimatedCost
}

$computedSavingsRate = $SavingsRatePct
if (($computedSavingsRate -eq 0) -and ($BaselineCost -gt 0)) {
  $computedSavingsRate = [decimal]::Round(($computedSavings / $BaselineCost) * 100, 2)
}

$computedCostStatus = $CostStatus
$exceedsBaselineGuard = ($BaselineCost -gt 0) -and ($EstimatedCost -gt ($BaselineCost * 2))
if (($CostLimit -gt 0) -and ($EstimatedCost -gt $CostLimit)) {
  $computedCostStatus = 'over_limit'
  if ($ContinueOrStop -eq 'continue') {
    $ContinueOrStop = 'needs_confirmation'
  }
} elseif ($exceedsBaselineGuard) {
  $computedCostStatus = 'over_baseline_guard'
  if ($ContinueOrStop -eq 'continue') {
    $ContinueOrStop = 'needs_confirmation'
  }
}

$date = (Get-Date).ToString('yyyy-MM-dd')
$successValue = if ($TaskSuccess) { 'true' } else { 'false' }
$recordScript = Join-Path $PSScriptRoot 'record-qianlima-usage.ps1'
$canonicalLedgerPath = Join-Path $ledgerDir 'runs.jsonl'
$recordArgs = @{
  WorkflowId = $WorkflowId
  RunId = $safeRunId
  TaskName = $TaskName
  Provider = $ModelProvider
  Model = $ModelName
  WorkloadType = $WorkloadType
  TokenizerId = $TokenizerId
  TokenizerVersion = $TokenizerVersion
  TokenMeasurementMethod = $TokenMeasurementMethod
  TokenMeasurementReference = $TokenMeasurementReference
  InputTokens = $InputTokens
  OutputTokens = $OutputTokens
  CacheHitTokens = $CachedInputTokens
  ReasoningTokens = $ReasoningTokens
  ToolCost = $ToolCost
  ToolCostCurrency = $ToolCostCurrency
  EstimatedCost = $EstimatedCost
  Currency = $Currency
  BillingTolerancePct = $BillingTolerancePct
  BaselineCost = $BaselineCost
  CostLimit = $CostLimit
  CostStatus = $computedCostStatus
  SavingsSource = $SavingsSource
  ContinueOrStop = $ContinueOrStop
  EstimatedSavings = $computedSavings
  SavingsRatePct = $computedSavingsRate
  Status = if ($TaskSuccess) { 'completed' } else { 'partial' }
  Notes = 'YAML evidence generated by new-usage-record.ps1.'
  LedgerPath = $canonicalLedgerPath
  PassThru = $true
}
if ($null -ne $EstimatedInputTokens) { $recordArgs.EstimatedInputTokens = $EstimatedInputTokens }
if ($null -ne $EstimatedOutputTokens) { $recordArgs.EstimatedOutputTokens = $EstimatedOutputTokens }
if ($null -ne $BilledCost) {
  $recordArgs.BilledCost = $BilledCost
  $recordArgs.BilledCostCurrency = $BilledCostCurrency
}
$canonicalRecord = & $recordScript @recordArgs

$content = @"
run:
  run_id: $safeRunId
  date: $date
  task_name: $(ConvertTo-YamlScalar $TaskName)
  workflow_id: $(ConvertTo-YamlScalar $WorkflowId)
  model_provider: $(ConvertTo-YamlScalar $ModelProvider)
  model_name: $(ConvertTo-YamlScalar $ModelName)

token_usage:
  tokenizer:
    id: $(ConvertTo-YamlScalar $TokenizerId)
    version: $(ConvertTo-YamlScalar $TokenizerVersion)
    workload_type: $(ConvertTo-YamlScalar $WorkloadType)
    measurement_method: $(ConvertTo-YamlScalar $TokenMeasurementMethod)
    measurement_reference: $(ConvertTo-YamlScalar $TokenMeasurementReference)
  estimate:
    input_tokens: $estimatedInputValue
    output_tokens: $estimatedOutputValue
    total_tokens: $estimatedTotalValue
  actual:
    input_tokens: $InputTokens
    output_tokens: $OutputTokens
    cached_input_tokens: $CachedInputTokens
    reasoning_tokens: $ReasoningTokens
    total_tokens: $totalTokens
  variance:
    input_tokens_delta: $inputTokenDeltaValue
    output_tokens_delta: $outputTokenDeltaValue
    total_tokens_delta: $totalTokenDeltaValue
    input_tokens_delta_pct: $inputTokenDeltaPctValue
    total_tokens_delta_pct: $totalTokenDeltaPctValue

cost:
  currency: $(ConvertTo-YamlScalar $Currency)
  estimated_cost: $EstimatedCost
  model_cost: $modelCost
  tool_cost: $ToolCost
  tool_cost_currency: $(ConvertTo-YamlScalar $ToolCostCurrency)
  baseline_cost: $BaselineCost
  estimated_savings: $computedSavings
  estimated_savings_rate_pct: $computedSavingsRate
  cost_limit: $CostLimit
  cost_status: $computedCostStatus
  savings_source: $(ConvertTo-YamlScalar $SavingsSource)
  continue_or_stop: $ContinueOrStop
  note: Replace placeholder values when exact model metering is available.

billing_reconciliation:
  status: $billingStatus
  billed_cost: $billedCostValue
  billed_cost_currency: $(if ($null -ne $BilledCost) { $BilledCostCurrency } else { 'unknown' })
  estimated_cost_delta: $costDeltaValue
  estimated_cost_delta_pct: $costDeltaPctValue
  tolerance_pct: $BillingTolerancePct

pricing:
  metering_method: $(ConvertTo-YamlScalar $costMeteringMethod)
  catalog_version: $(ConvertTo-YamlScalar $pricingCatalogVersion)
  source_url: $(ConvertTo-YamlScalar $pricingSourceUrl)
  verified_at: $(ConvertTo-YamlScalar $pricingVerifiedAt)

canonical_ledger:
  schema_version: $($canonicalRecord.Record.schema_version)
  path: usage-ledger/runs.jsonl
  run_id: $safeRunId

realtime_cost_card:
  visible_to_user: true
  template: .qianlima/templates/realtime-cost-card_template.md
  generator: .qianlima/scripts/new-cost-card.ps1
  currency: $(ConvertTo-YamlScalar $Currency)
  current_estimated_cost: $EstimatedCost
  cost_limit: $CostLimit
  baseline_cost: $BaselineCost
  estimated_savings: $computedSavings
  estimated_savings_rate_pct: $computedSavingsRate
  primary_savings_source: $(ConvertTo-YamlScalar $SavingsSource)
  continue_or_stop: $ContinueOrStop

context:
  startup_profile: unknown
  files_loaded: []
  compression_used: unknown
  context_policy: .qianlima/context-policy.yaml
  loaded_file_count: 0

result:
  output_file: $(ConvertTo-YamlScalar $OutputFile)
  data_sources_used: []
  user_visible_cost_summary: true
  savings_summary_present: true
  task_success: $successValue
  user_edit_required: unknown
  source_citation_present: unknown
  elapsed_seconds: 0
  performance_notes: replace_me
  notes: Generated by new-usage-record.ps1.
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
Write-Host "Usage ledger created: $path"
Write-Host "Canonical usage ledger appended: $($canonicalRecord.LedgerPath)"
