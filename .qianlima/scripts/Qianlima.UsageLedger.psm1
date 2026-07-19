Set-StrictMode -Version Latest

function Get-QianlimaLedgerValue {
  param(
    [Parameter(Mandatory = $true)] [object]$Record,
    [Parameter(Mandatory = $true)] [string]$Name,
    [object]$Default = $null
  )

  $property = $Record.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function ConvertTo-QianlimaDecimal {
  param([object]$Value, [decimal]$Default = 0)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
  try { return [decimal]$Value } catch { throw "Ledger cost value is invalid: $Value" }
}

function ConvertTo-QianlimaUsageLedgerRecord {
  param([Parameter(Mandatory = $true)] [object]$Record)

  $schemaVersion = [int](Get-QianlimaLedgerValue -Record $Record -Name 'schema_version' -Default 1)
  if ($schemaVersion -lt 1 -or $schemaVersion -gt 2) {
    throw "Unsupported usage-ledger schema version: $schemaVersion"
  }

  $isV2 = $schemaVersion -ge 2
  $currency = if ($isV2) {
    [string](Get-QianlimaLedgerValue -Record $Record -Name 'currency' -Default '')
  } else {
    'USD'
  }
  if ([string]::IsNullOrWhiteSpace($currency)) {
    throw 'Usage-ledger records must declare a currency.'
  }
  $currency = $currency.ToUpperInvariant()
  if ($currency -notmatch '^[A-Z]{3}$') { throw "Usage-ledger currency is invalid: $currency" }

  $estimatedCost = if ($isV2) {
    ConvertTo-QianlimaDecimal (Get-QianlimaLedgerValue -Record $Record -Name 'estimated_cost')
  } else {
    ConvertTo-QianlimaDecimal (Get-QianlimaLedgerValue -Record $Record -Name 'estimated_cost_usd')
  }
  $toolCost = if ($isV2) {
    ConvertTo-QianlimaDecimal (Get-QianlimaLedgerValue -Record $Record -Name 'tool_cost')
  } else {
    [decimal]0
  }
  $modelCost = if ($isV2) {
    ConvertTo-QianlimaDecimal (Get-QianlimaLedgerValue -Record $Record -Name 'model_cost' -Default ($estimatedCost - $toolCost))
  } else {
    $estimatedCost
  }
  if ($estimatedCost -lt 0 -or $modelCost -lt 0 -or $toolCost -lt 0 -or $toolCost -gt $estimatedCost) {
    throw 'Usage-ledger cost components are invalid.'
  }

  [PSCustomObject]@{
    source_schema_version = $schemaVersion
    run_id = [string](Get-QianlimaLedgerValue -Record $Record -Name 'run_id' -Default '')
    workflow_id = [string](Get-QianlimaLedgerValue -Record $Record -Name 'workflow_id' -Default '')
    task_name = [string](Get-QianlimaLedgerValue -Record $Record -Name 'task_name' -Default '')
    provider = [string](Get-QianlimaLedgerValue -Record $Record -Name 'provider' -Default '')
    model = [string](Get-QianlimaLedgerValue -Record $Record -Name 'model' -Default '')
    workload_type = [string](Get-QianlimaLedgerValue -Record $Record -Name 'workload_type' -Default 'unknown')
    tokenizer_id = [string](Get-QianlimaLedgerValue -Record $Record -Name 'tokenizer_id' -Default 'unknown')
    tokenizer_version = [string](Get-QianlimaLedgerValue -Record $Record -Name 'tokenizer_version' -Default 'unknown')
    token_measurement_method = [string](Get-QianlimaLedgerValue -Record $Record -Name 'token_measurement_method' -Default 'unknown')
    token_measurement_reference = [string](Get-QianlimaLedgerValue -Record $Record -Name 'token_measurement_reference' -Default '')
    input_tokens = [double](Get-QianlimaLedgerValue -Record $Record -Name 'input_tokens' -Default 0)
    output_tokens = [double](Get-QianlimaLedgerValue -Record $Record -Name 'output_tokens' -Default 0)
    cache_hit_tokens = [double](Get-QianlimaLedgerValue -Record $Record -Name 'cache_hit_tokens' -Default 0)
    reasoning_tokens = [double](Get-QianlimaLedgerValue -Record $Record -Name 'reasoning_tokens' -Default 0)
    estimated_input_tokens = Get-QianlimaLedgerValue -Record $Record -Name 'estimated_input_tokens'
    estimated_output_tokens = Get-QianlimaLedgerValue -Record $Record -Name 'estimated_output_tokens'
    input_token_delta = Get-QianlimaLedgerValue -Record $Record -Name 'input_token_delta'
    output_token_delta = Get-QianlimaLedgerValue -Record $Record -Name 'output_token_delta'
    total_token_delta = Get-QianlimaLedgerValue -Record $Record -Name 'total_token_delta'
    input_token_delta_pct = Get-QianlimaLedgerValue -Record $Record -Name 'input_token_delta_pct'
    total_token_delta_pct = Get-QianlimaLedgerValue -Record $Record -Name 'total_token_delta_pct'
    tool_calls = [int](Get-QianlimaLedgerValue -Record $Record -Name 'tool_calls' -Default 0)
    rows_read = [int](Get-QianlimaLedgerValue -Record $Record -Name 'rows_read' -Default 0)
    duration_seconds = [double](Get-QianlimaLedgerValue -Record $Record -Name 'duration_seconds' -Default 0)
    startup_ms = [double](Get-QianlimaLedgerValue -Record $Record -Name 'startup_ms' -Default 0)
    routing_ms = [double](Get-QianlimaLedgerValue -Record $Record -Name 'routing_ms' -Default 0)
    context_load_ms = [double](Get-QianlimaLedgerValue -Record $Record -Name 'context_load_ms' -Default 0)
    tool_ms = [double](Get-QianlimaLedgerValue -Record $Record -Name 'tool_ms' -Default 0)
    model_ms = [double](Get-QianlimaLedgerValue -Record $Record -Name 'model_ms' -Default 0)
    first_useful_output_ms = [double](Get-QianlimaLedgerValue -Record $Record -Name 'first_useful_output_ms' -Default 0)
    currency = $currency
    estimated_cost = $estimatedCost
    model_cost = $modelCost
    tool_cost = $toolCost
    baseline_cost = if ($isV2) { ConvertTo-QianlimaDecimal (Get-QianlimaLedgerValue -Record $Record -Name 'baseline_cost') } else { [decimal]0 }
    billed_cost = if ($isV2) { Get-QianlimaLedgerValue -Record $Record -Name 'billed_cost' } else { $null }
    outcome_units = [int](Get-QianlimaLedgerValue -Record $Record -Name 'outcome_units' -Default 0)
    outcome_unit = [string](Get-QianlimaLedgerValue -Record $Record -Name 'outcome_unit' -Default '')
    status = [string](Get-QianlimaLedgerValue -Record $Record -Name 'status' -Default '')
    notes = [string](Get-QianlimaLedgerValue -Record $Record -Name 'notes' -Default '')
    recorded_at = [string](Get-QianlimaLedgerValue -Record $Record -Name 'recorded_at' -Default '')
  }
}

function Get-QianlimaUsageLedgerRecords {
  param([Parameter(Mandatory = $true)] [string]$LedgerPath)

  if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) { return @() }
  $records = [System.Collections.Generic.List[object]]::new()
  $lineNumber = 0
  foreach ($line in @(Get-Content -LiteralPath $LedgerPath -Encoding UTF8)) {
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
      $records.Add((ConvertTo-QianlimaUsageLedgerRecord -Record ($line | ConvertFrom-Json)))
    } catch {
      Write-Warning "Skipping invalid usage-ledger line ${lineNumber}: $($_.Exception.Message)"
    }
  }
  return @($records)
}

function Get-QianlimaBaselineForCurrency {
  param(
    [object]$BaselineDocument,
    [Parameter(Mandatory = $true)] [string]$WorkflowId,
    [Parameter(Mandatory = $true)] [string]$Currency
  )

  if ($null -eq $BaselineDocument) { return $null }
  $workflows = $BaselineDocument.PSObject.Properties['workflows']
  if ($null -eq $workflows) { return $null }
  $workflow = $workflows.Value.PSObject.Properties[$WorkflowId]
  if ($null -eq $workflow) { return $null }

  $currencyBaselines = $workflow.Value.PSObject.Properties['currencies']
  if ($null -ne $currencyBaselines) {
    $match = $currencyBaselines.Value.PSObject.Properties[$Currency]
    if ($null -eq $match) { return $null }
    return ConvertTo-QianlimaDecimal (Get-QianlimaLedgerValue -Record $match.Value -Name 'baseline_cost')
  }

  # Schema v1 stored USD-only values without an explicit currency field.
  if ($Currency -eq 'USD') {
    $legacy = $workflow.Value.PSObject.Properties['baseline_cost_usd']
    if ($null -ne $legacy) { return ConvertTo-QianlimaDecimal $legacy.Value }
  }
  return $null
}

Export-ModuleMember -Function ConvertTo-QianlimaUsageLedgerRecord, Get-QianlimaUsageLedgerRecords, Get-QianlimaBaselineForCurrency
