<#
.SYNOPSIS
Computes and stores a currency-scoped median cost baseline for a workflow.
.DESCRIPTION
Reads the canonical usage-ledger/runs.jsonl through the shared parser and
calculates a median from completed runs in one currency. A baseline is never
calculated from mixed currencies. Existing schema v1 USD baselines are read and
migrated to schema v2 when the same workflow is updated.
#>
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')]
  [string]$WorkflowId,

  [ValidateRange(3, 100)]
  [int]$SampleSize = 5,

  [string]$Currency = '',
  [string]$LedgerPath = '',
  [string]$BaselinePath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ledgerDirectory = Join-Path $projectRoot '.qianlima\usage-ledger'
if ([string]::IsNullOrWhiteSpace($LedgerPath)) {
  $LedgerPath = Join-Path $ledgerDirectory 'runs.jsonl'
}
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
  $BaselinePath = Join-Path $ledgerDirectory 'baselines.json'
}
$modulePath = Join-Path $PSScriptRoot 'Qianlima.UsageLedger.psm1'
Import-Module $modulePath -Force

if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) {
  throw "Usage ledger not found: $LedgerPath"
}

$workflowRuns = @(Get-QianlimaUsageLedgerRecords -LedgerPath $LedgerPath |
  Where-Object { $_.workflow_id -eq $WorkflowId -and $_.status -eq 'completed' })
if ($workflowRuns.Count -eq 0) { throw "No completed runs found for $WorkflowId." }

if ([string]::IsNullOrWhiteSpace($Currency)) {
  $currencies = @($workflowRuns | Select-Object -ExpandProperty currency -Unique | Sort-Object)
  if ($currencies.Count -ne 1) {
    throw "Completed runs for $WorkflowId use multiple currencies ($($currencies -join ', ')). Specify -Currency."
  }
  $Currency = $currencies[0]
}
$Currency = $Currency.ToUpperInvariant()
if ($Currency -notmatch '^[A-Z]{3}$') { throw 'Currency must be a three-letter code.' }

$runs = @($workflowRuns |
  Where-Object { $_.currency -eq $Currency } |
  Sort-Object recorded_at -Descending |
  Select-Object -First $SampleSize)
if ($runs.Count -lt $SampleSize) {
  throw "Baseline needs $SampleSize completed $Currency runs for $WorkflowId; found $($runs.Count)."
}

$costs = @($runs | ForEach-Object { [decimal]$_.estimated_cost } | Sort-Object)
$middle = [int][math]::Floor($costs.Count / 2)
$median = if ($costs.Count % 2 -eq 1) { $costs[$middle] } else { ($costs[$middle - 1] + $costs[$middle]) / 2 }
$median = [decimal]::Round($median, 6)

$document = [PSCustomObject]@{ schema_version = 2; workflows = [PSCustomObject]@{} }
if (Test-Path -LiteralPath $BaselinePath -PathType Leaf) {
  $document = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
}
if (-not ($document.PSObject.Properties.Name -contains 'schema_version')) {
  $document | Add-Member -MemberType NoteProperty -Name schema_version -Value 2
} else { $document.schema_version = 2 }
if (-not ($document.PSObject.Properties.Name -contains 'workflows')) {
  $document | Add-Member -MemberType NoteProperty -Name workflows -Value ([PSCustomObject]@{})
}

$workflowProperty = $document.workflows.PSObject.Properties[$WorkflowId]
if ($null -eq $workflowProperty) {
  $workflowValue = [PSCustomObject]@{ currencies = [PSCustomObject]@{} }
  $document.workflows | Add-Member -MemberType NoteProperty -Name $WorkflowId -Value $workflowValue
} else {
  $workflowValue = $workflowProperty.Value
  if (-not ($workflowValue.PSObject.Properties.Name -contains 'currencies')) {
    $currencyMap = [PSCustomObject]@{}
    $legacyCost = $workflowValue.PSObject.Properties['baseline_cost_usd']
    if ($null -ne $legacyCost) {
      $currencyMap | Add-Member -MemberType NoteProperty -Name USD -Value ([PSCustomObject]@{
        currency = 'USD'
        baseline_cost = [decimal]$legacyCost.Value
        sample_size = if ($workflowValue.PSObject.Properties['sample_size']) { $workflowValue.sample_size } else { 0 }
        method = if ($workflowValue.PSObject.Properties['method']) { $workflowValue.method } else { 'legacy_usd_baseline' }
        calculated_at = if ($workflowValue.PSObject.Properties['calculated_at']) { $workflowValue.calculated_at } else { '' }
      })
    }
    $workflowValue | Add-Member -MemberType NoteProperty -Name currencies -Value $currencyMap
    foreach ($legacyName in @('baseline_cost_usd', 'sample_size', 'method', 'calculated_at')) {
      if ($workflowValue.PSObject.Properties[$legacyName]) { $workflowValue.PSObject.Properties.Remove($legacyName) }
    }
  }
}

$baseline = [PSCustomObject]@{
  currency = $Currency
  baseline_cost = $median
  sample_size = $SampleSize
  method = 'median_completed_run_cost'
  calculated_at = (Get-Date).ToUniversalTime().ToString('o')
}
$existingCurrency = $workflowValue.currencies.PSObject.Properties[$Currency]
if ($null -eq $existingCurrency) {
  $workflowValue.currencies | Add-Member -MemberType NoteProperty -Name $Currency -Value $baseline
} else {
  $existingCurrency.Value = $baseline
}

$baselineDirectory = Split-Path -Parent $BaselinePath
if (-not (Test-Path -LiteralPath $baselineDirectory -PathType Container)) {
  New-Item -ItemType Directory -Path $baselineDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllText($BaselinePath, ($document | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
Write-Host "Baseline saved: $WorkflowId / $Currency = $($median.ToString('0.000000'))"
