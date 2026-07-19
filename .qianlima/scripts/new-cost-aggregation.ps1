<#
.SYNOPSIS
Compatibility entrypoint for the canonical Qianlima cost dashboard.
.DESCRIPTION
Historical versions parsed per-run YAML evidence while the primary dashboard
parsed JSONL, causing the two reports to disagree. JSONL is now the canonical
append-only ledger and this entrypoint delegates to the shared dashboard so all
cost aggregation has identical currency and schema handling.
#>
param(
  [string]$OutputPath = '',
  [ValidateRange(1, 365)]
  [int]$DaysBack = 30,
  [switch]$JsonOnly = $false
)

$ErrorActionPreference = 'Stop'
if ($JsonOnly) {
  throw 'JsonOnly is not available. Use runs.jsonl directly through Qianlima.UsageLedger.psm1 for structured data.'
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $projectRoot '.qianlima\reports\cost-aggregation.md'
}
$dashboardScript = Join-Path $PSScriptRoot 'new-qianlima-cost-dashboard.ps1'
& $dashboardScript -Days $DaysBack -OutputPath $OutputPath
Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8
