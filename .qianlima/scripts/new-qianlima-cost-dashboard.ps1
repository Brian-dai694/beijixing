<#
.SYNOPSIS
Build a currency-safe Markdown cost dashboard from the canonical JSONL ledger.
.DESCRIPTION
Reads .qianlima/usage-ledger/runs.jsonl through the shared ledger parser. Schema
v1 USD records remain readable, while schema v2 records preserve their declared
currency and effective-cost breakdown. Amounts are never aggregated across
currencies because the ledger does not hold timestamped FX evidence.
#>
param(
  [ValidateRange(1, 365)]
  [int]$Days = 30,
  [string]$OutputPath = '',
  [string]$LedgerPath = '',
  [string]$BaselinePath = ''
)

$ErrorActionPreference = 'Stop'

function Get-Amount([object[]]$Items) {
  $sum = [decimal]0
  foreach ($item in @($Items)) { $sum += [decimal]$item.estimated_cost }
  return [decimal]::Round($sum, 6)
}

function Format-Amount([decimal]$Amount, [string]$Currency) {
  return ($Currency + ' ' + $Amount.ToString('0.000000'))
}

function Get-Bar([decimal]$Value, [decimal]$Maximum) {
  if ($Maximum -le 0 -or $Value -le 0) { return '' }
  return ('#' * [math]::Max(1, [math]::Ceiling(([double]$Value / [double]$Maximum) * 20)))
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($LedgerPath)) {
  $LedgerPath = Join-Path $projectRoot '.qianlima\usage-ledger\runs.jsonl'
}
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
  $BaselinePath = Join-Path $projectRoot '.qianlima\usage-ledger\baselines.json'
}
$modulePath = Join-Path $PSScriptRoot 'Qianlima.UsageLedger.psm1'
Import-Module $modulePath -Force

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $projectRoot '.qianlima\reports\cost-dashboard.md'
}

$cutoff = (Get-Date).ToUniversalTime().AddDays(-($Days - 1)).Date
$weekCutoff = (Get-Date).ToUniversalTime().AddDays(-6).Date
$periodRuns = [System.Collections.Generic.List[object]]::new()
foreach ($run in @(Get-QianlimaUsageLedgerRecords -LedgerPath $LedgerPath)) {
  if ([string]::IsNullOrWhiteSpace($run.recorded_at)) { continue }
  try {
    $recordedAt = [datetimeoffset]::Parse($run.recorded_at).ToUniversalTime()
    if ($recordedAt -ge $cutoff) {
      $run | Add-Member -NotePropertyName recorded_at_utc -NotePropertyValue $recordedAt
      $periodRuns.Add($run)
    }
  } catch { Write-Warning "Skipping run with invalid recorded_at: $($run.run_id)" }
}

$baselineDocument = $null
if (Test-Path -LiteralPath $BaselinePath -PathType Leaf) {
  $baselineDocument = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$completedRuns = @($periodRuns | Where-Object { $_.status -eq 'completed' })
$currencyRows = @($periodRuns | Group-Object currency | ForEach-Object {
  $currency = $_.Name
  $weekRuns = @($_.Group | Where-Object { $_.recorded_at_utc -ge $weekCutoff })
  [PSCustomObject]@{
    Currency = $currency
    Runs = $_.Count
    WeekCost = Get-Amount $weekRuns
    TotalCost = Get-Amount $_.Group
  }
} | Sort-Object Currency)

$workflowRows = @($periodRuns | Group-Object { $_.workflow_id + '|' + $_.currency } | ForEach-Object {
  $sample = $_.Group[0]
  $baseline = Get-QianlimaBaselineForCurrency -BaselineDocument $baselineDocument -WorkflowId $sample.workflow_id -Currency $sample.currency
  $overruns = if ($null -ne $baseline -and $baseline -gt 0) {
    @($_.Group | Where-Object { $_.estimated_cost -gt ($baseline * 2) }).Count
  } else { 0 }
  [PSCustomObject]@{
    Workflow = $sample.workflow_id
    Currency = $sample.currency
    Runs = $_.Count
    Cost = Get-Amount $_.Group
    Baseline = $baseline
    Overruns = $overruns
  }
} | Sort-Object Currency, @{ Expression = 'Cost'; Descending = $true }, Workflow)

$dailyRows = @($periodRuns | Group-Object { $_.recorded_at_utc.ToString('yyyy-MM-dd') + '|' + $_.currency } | ForEach-Object {
  $sample = $_.Group[0]
  [PSCustomObject]@{
    Date = $sample.recorded_at_utc.ToString('yyyy-MM-dd')
    Currency = $sample.currency
    Runs = $_.Count
    Cost = Get-Amount $_.Group
  }
} | Sort-Object Date, Currency)
$dailyMaximums = @{}
foreach ($group in @($dailyRows | Group-Object Currency)) {
  $dailyMaximums[$group.Name] = [decimal](($group.Group | Measure-Object -Property Cost -Maximum).Maximum)
}

$outcomeRows = @($completedRuns | Where-Object { $_.outcome_units -gt 0 } | Group-Object { $_.workflow_id + '|' + $_.currency } | ForEach-Object {
  $sample = $_.Group[0]
  $units = [int](($_.Group | Measure-Object -Property outcome_units -Sum).Sum)
  [PSCustomObject]@{
    Workflow = $sample.workflow_id
    Currency = $sample.currency
    Units = $units
    UnitName = (@($_.Group | Select-Object -ExpandProperty outcome_unit -Unique | Where-Object { $_ }) -join ', ')
    CostPerOutcome = if ($units -gt 0) { [decimal]::Round((Get-Amount $_.Group) / $units, 6) } else { [decimal]0 }
  }
} | Sort-Object Currency, Workflow)

$latencyFields = @('startup_ms', 'routing_ms', 'context_load_ms', 'tool_ms', 'model_ms', 'first_useful_output_ms')
$latencyRows = foreach ($field in $latencyFields) {
  $values = @($periodRuns | ForEach-Object {
    $value = [double]$_.$field
    if ($value -gt 0) { $value }
  })
  if ($values.Count -gt 0) {
    [PSCustomObject]@{ Label = ($field -replace '_', ' '); Samples = $values.Count; Average = [math]::Round((($values | Measure-Object -Average).Average), 1) }
  }
}

$currencyTable = if ($currencyRows.Count -eq 0) { '| No records | 0 | - | - |' } else {
  ($currencyRows | ForEach-Object { "| $($_.Currency) | $($_.Runs) | $(Format-Amount $_.WeekCost $_.Currency) | $(Format-Amount $_.TotalCost $_.Currency) |" }) -join "`n"
}
$workflowTable = if ($workflowRows.Count -eq 0) { '| No records | - | 0 | - | not set | 0 |' } else {
  ($workflowRows | ForEach-Object {
    $baselineText = if ($null -eq $_.Baseline) { 'not set' } else { Format-Amount $_.Baseline $_.Currency }
    "| $($_.Workflow) | $($_.Currency) | $($_.Runs) | $(Format-Amount $_.Cost $_.Currency) | $baselineText | $($_.Overruns) |"
  }) -join "`n"
}
$dailyTable = if ($dailyRows.Count -eq 0) { '| No records | - | 0 | - | |' } else {
  ($dailyRows | ForEach-Object { "| $($_.Date) | $($_.Currency) | $($_.Runs) | $(Format-Amount $_.Cost $_.Currency) | $(Get-Bar $_.Cost $dailyMaximums[$_.Currency]) |" }) -join "`n"
}
$outcomeTable = if ($outcomeRows.Count -eq 0) { '| No completed outcome units recorded yet | - | - | - | - |' } else {
  ($outcomeRows | ForEach-Object { "| $($_.Workflow) | $($_.Currency) | $($_.Units) | $($_.UnitName) | $(Format-Amount $_.CostPerOutcome $_.Currency) |" }) -join "`n"
}
$latencyTable = if (@($latencyRows).Count -eq 0) { '| No latency samples recorded yet | 0 | - |' } else {
  ($latencyRows | ForEach-Object { "| $($_.Label) | $($_.Samples) | $($_.Average) ms |" }) -join "`n"
}

$zeroCost = @($periodRuns | Where-Object { $_.estimated_cost -eq 0 }).Count
$legacyRecords = @($periodRuns | Where-Object { $_.source_schema_version -eq 1 }).Count
$overrunCount = [int](($workflowRows | Measure-Object -Property Overruns -Sum).Sum)
$markdown = @"
# Qianlima Cost Dashboard

Generated at: $((Get-Date).ToUniversalTime().ToString('o'))
Window: last $Days days
Ledger: `.qianlima/usage-ledger/runs.jsonl` (private, append-only)

## Cost Card

| Currency | Runs recorded | Last 7 days cost | Last $Days days cost |
|---|---:|---:|---:|
$currencyTable

Amounts are intentionally not totaled across currencies. No FX conversion is applied unless a separately evidenced conversion is recorded.

## Workflow Cost

| Workflow | Currency | Runs | Cost | Baseline per run | >2x baseline |
|---|---|---:|---:|---:|---:|
$workflowTable

## Daily Trend

| Date | Currency | Runs | Cost | Trend |
|---|---|---:|---:|---|
$dailyTable

## Cost Per Outcome

| Workflow | Currency | Outcome units | Unit | Cost per outcome |
|---|---|---:|---|---:|
$outcomeTable

## Latency Breakdown

| Stage | Samples | Average |
|---|---:|---:|
$latencyTable

## Data Quality

| Metric | Value |
|---|---:|
| Total records | $($periodRuns.Count) |
| Completed runs | $($completedRuns.Count) |
| Schema v1 USD compatibility records | $legacyRecords |
| Cost = 0 records | $zeroCost |
| Workflow runs above 2x baseline | $overrunCount |

## Interpretation

- Schema v2 records retain tokenizer provenance, measured-versus-estimated tokens, and model/tool cost split.
- A baseline only applies when it has the same currency as the run.
- Zero-cost local scripts remain execution evidence; they are not model-usage estimates.
- Latency averages use only records that supplied the corresponding measured field.
"@

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllText($OutputPath, $markdown, [System.Text.UTF8Encoding]::new($false))
Write-Host "Cost dashboard generated: $OutputPath"
