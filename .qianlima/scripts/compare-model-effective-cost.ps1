<#
.SYNOPSIS
  Compare effective model costs from target-model token measurements.
.DESCRIPTION
  Reads a local JSON measurement file produced from provider usage, an official
  token counter, or a versioned local encoder. It prices each entry against
  model-pricing.json, ranks only models in the same currency, and never calls
  provider APIs or reads credentials.

  The measurement file schema is:
  {
    "workload_type": "typescript",
    "models": [{
      "provider": "deepseek", "model": "deepseek-v4-flash",
      "input_tokens": 1000, "output_tokens": 200,
      "cached_input_tokens": 0, "reasoning_tokens": 0,
      "tokenizer_id": "provider-reported", "tokenizer_version": "2026-07",
      "measurement_method": "provider_usage",
      "measurement_reference": "run trace or official counter reference",
      "tool_cost": 0,
      "tool_cost_currency": "USD"
    }]
  }

  Token convention: output_tokens is the provider output total and INCLUDES reasoning_tokens;
  cached_input_tokens is a subset of input_tokens. Both are diagnostic breakdowns, so reasoning
  is already priced at the output rate and neither is charged twice.
.PARAMETER MeasurementsPath
  Local JSON measurement file. The file contains no credentials.
.PARAMETER CatalogPath
  Pricing catalog path. Defaults to ../model-pricing.json.
.PARAMETER AsJson
  Emit the comparison result as JSON.
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$MeasurementsPath,
  [string]$CatalogPath = '',
  [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$allowedMethods = @('provider_usage', 'official_counter', 'local_encoder', 'estimate')

if (-not (Test-Path -LiteralPath $MeasurementsPath -PathType Leaf)) {
  throw "Measurements file is missing: $MeasurementsPath"
}
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
  $CatalogPath = Join-Path $PSScriptRoot '..\model-pricing.json'
}
if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
  throw "Pricing catalog is missing: $CatalogPath"
}

$measurements = Get-Content -LiteralPath $MeasurementsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$workloadType = if ([string]::IsNullOrWhiteSpace($measurements.workload_type)) { 'unknown' } else { [string]$measurements.workload_type }
$records = @()

foreach ($entry in @($measurements.models)) {
  if ([string]::IsNullOrWhiteSpace($entry.provider) -or [string]::IsNullOrWhiteSpace($entry.model)) {
    throw 'Every model measurement requires provider and model.'
  }
  if ($allowedMethods -notcontains [string]$entry.measurement_method) {
    throw "Unsupported measurement_method for $($entry.provider)/$($entry.model)."
  }

  $inputTokens = [int]$entry.input_tokens
  $outputTokens = [int]$entry.output_tokens
  $cachedInputTokens = if ($null -eq $entry.cached_input_tokens) { 0 } else { [int]$entry.cached_input_tokens }
  $reasoningTokens = if ($null -eq $entry.reasoning_tokens) { 0 } else { [int]$entry.reasoning_tokens }
  $toolCost = if ($null -eq $entry.tool_cost) { 0 } else { [decimal]$entry.tool_cost }
  $toolCostCurrency = if ($null -eq $entry.tool_cost_currency) { '' } else { ([string]$entry.tool_cost_currency).ToUpperInvariant() }
  foreach ($value in @($inputTokens, $outputTokens, $cachedInputTokens, $reasoningTokens, $toolCost)) {
    if ($value -lt 0) { throw "Token counts and tool_cost must be non-negative for $($entry.provider)/$($entry.model)." }
  }
  if ($cachedInputTokens -gt $inputTokens) {
    throw "cached_input_tokens cannot exceed input_tokens for $($entry.provider)/$($entry.model)."
  }
  if ($reasoningTokens -gt $outputTokens) {
    throw "reasoning_tokens cannot exceed output_tokens for $($entry.provider)/$($entry.model)."
  }
  if ($toolCost -gt 0 -and [string]::IsNullOrWhiteSpace($toolCostCurrency)) {
    throw "tool_cost_currency is required when tool_cost is non-zero for $($entry.provider)/$($entry.model)."
  }
  if (-not [string]::IsNullOrWhiteSpace($toolCostCurrency) -and $toolCostCurrency -notmatch '^[A-Z]{3}$') {
    throw "tool_cost_currency must be a three-letter code for $($entry.provider)/$($entry.model)."
  }

  $priceEntry = @($catalog.models | Where-Object { $_.provider -eq $entry.provider -and $_.model -eq $entry.model } | Select-Object -First 1)
  if ($priceEntry.Count -eq 0) {
    $sourceOnly = @($catalog.source_only_providers | Where-Object { $_.provider -eq $entry.provider } | Select-Object -First 1)
    $records += ,[PSCustomObject]@{
      provider = [string]$entry.provider
      model = [string]$entry.model
      workload_type = $workloadType
      tokenizer_id = [string]$entry.tokenizer_id
      tokenizer_version = [string]$entry.tokenizer_version
      measurement_method = [string]$entry.measurement_method
      measurement_reference = [string]$entry.measurement_reference
      input_tokens = $inputTokens
      output_tokens = $outputTokens
      cached_input_tokens = $cachedInputTokens
      reasoning_tokens = $reasoningTokens
      status = 'source_only'
      currency = ''
      tool_cost_currency = $toolCostCurrency
      effective_cost = $null
      source_url = if ($sourceOnly.Count -gt 0) { [string]$sourceOnly[0].source_url } else { '' }
      note = 'No verified catalog price. Refresh the official price before comparing this model.'
    }
    continue
  }

  $price = $priceEntry[0].pricing_per_million_tokens
  # Validate required price fields exist and are numeric; [decimal]$null silently yields 0 and would hide a malformed catalog.
  if ($null -eq $price) { throw "Catalog entry for $($entry.provider)/$($entry.model) is missing pricing_per_million_tokens." }
  $decimalPattern = '^\d+(\.\d+)?$'
  foreach ($field in @('input', 'output')) {
    $fieldValue = $price.$field
    if ($null -eq $fieldValue -or [string]$fieldValue -notmatch $decimalPattern) {
      throw "Catalog price field '$field' is missing or non-numeric for $($entry.provider)/$($entry.model)."
    }
  }
  if ($cachedInputTokens -gt 0 -and ($null -eq $price.cached_input -or [string]$price.cached_input -notmatch $decimalPattern)) {
    throw "Catalog price field 'cached_input' is missing or non-numeric but cached_input_tokens > 0 for $($entry.provider)/$($entry.model)."
  }
  $cachedInputPrice = if ($null -eq $price.cached_input) { 0 } else { [decimal]$price.cached_input }
  $priceCurrency = ([string]$priceEntry[0].currency).ToUpperInvariant()
  if ($toolCost -gt 0 -and $toolCostCurrency -ne $priceCurrency) {
    throw "tool_cost_currency ($toolCostCurrency) must match model currency ($priceCurrency) for $($entry.provider)/$($entry.model). Record a timestamped FX conversion before comparing cross-currency costs."
  }
  if ([string]::IsNullOrWhiteSpace($toolCostCurrency)) { $toolCostCurrency = $priceCurrency }
  $uncachedInputTokens = $inputTokens - $cachedInputTokens
  $inputCost = ($uncachedInputTokens / 1000000.0) * [decimal]$price.input
  $cachedInputCost = ($cachedInputTokens / 1000000.0) * $cachedInputPrice
  # output_tokens is the provider output total and already includes reasoning_tokens (see the
  # reasoning_tokens <= output_tokens check above), so output pricing already covers reasoning.
  $outputCost = ($outputTokens / 1000000.0) * [decimal]$price.output
  $effectiveCost = [decimal]::Round(($inputCost + $cachedInputCost + $outputCost + $toolCost), 8)
  $records += ,[PSCustomObject]@{
    provider = [string]$entry.provider
    model = [string]$entry.model
    workload_type = $workloadType
    tokenizer_id = [string]$entry.tokenizer_id
    tokenizer_version = [string]$entry.tokenizer_version
    measurement_method = [string]$entry.measurement_method
    measurement_reference = [string]$entry.measurement_reference
    input_tokens = $inputTokens
    output_tokens = $outputTokens
    cached_input_tokens = $cachedInputTokens
    reasoning_tokens = $reasoningTokens
    status = 'priced'
    currency = $priceCurrency
    tool_cost_currency = $toolCostCurrency
    effective_cost = $effectiveCost
    source_url = [string]$priceEntry[0].source_url
    note = if ([string]$entry.measurement_method -eq 'estimate') { 'Estimated tokens; reconcile with provider usage before making a pricing decision.' } else { 'Measured target-model tokens.' }
  }
}

$ranked = @()
foreach ($group in @($records | Where-Object { $_.status -eq 'priced' } | Group-Object currency)) {
  $rank = 0
  foreach ($record in @($group.Group | Sort-Object effective_cost, provider, model)) {
    $rank++
    $record | Add-Member -NotePropertyName rank_within_currency -NotePropertyValue $rank
    $ranked += ,$record
  }
}
foreach ($record in @($records | Where-Object { $_.status -ne 'priced' })) {
  $record | Add-Member -NotePropertyName rank_within_currency -NotePropertyValue $null
  $ranked += ,$record
}

$result = [PSCustomObject]@{
  workload_type = $workloadType
  measurement_count = @($records).Count
  comparison_rule = 'Only models with verified prices are ranked, and ranks are valid only within the same currency.'
  records = @($ranked)
}

if ($AsJson) {
  $result | ConvertTo-Json -Depth 8
} else {
  $result.records | Sort-Object currency, rank_within_currency, provider, model | Format-Table provider, model, workload_type, tokenizer_id, tokenizer_version, measurement_method, input_tokens, output_tokens, currency, effective_cost, rank_within_currency, status -AutoSize
}
