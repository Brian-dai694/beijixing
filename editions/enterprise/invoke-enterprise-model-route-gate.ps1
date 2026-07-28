<##
.SYNOPSIS
  Produces a governed model route plan without dispatching a model request.
.DESCRIPTION
  Model capability never grants tool, data, or business authority. Every route
  is version-pinned, evaluation-bound, budget-bound, and execution-disabled.
##>
param(
  [Parameter(Mandatory=$true)][string]$RequestPath,
  [string]$RegistryPath = '',
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $PSScriptRoot 'model-registry.example.json' }
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$issues = [System.Collections.Generic.List[string]]::new()
$model = @($registry.models | Where-Object { $_.model_id -eq $request.model_id } | Select-Object -First 1)
if ($null -eq $model) { [void]$issues.Add('unknown_model') }
else {
  if ([string]::IsNullOrWhiteSpace([string]$request.model_version) -or [string]$request.model_version -ne [string]$model.version) { [void]$issues.Add('version_not_pinned') }
  if ([string]$model.status -ne 'production_approved') { [void]$issues.Add('model_not_production_approved') }
  if (@($model.allowed_data) -notcontains [string]$request.data_classification) { [void]$issues.Add('data_classification_denied') }
  if ([int]$request.max_calls -gt [int]$model.max_calls -or [double]$request.max_cost_usd -gt [double]$model.max_cost_usd -or [int]$request.max_latency_ms -gt [int]$model.max_latency_ms) { [void]$issues.Add('model_budget_exceeded') }
  foreach ($field in @('structured_output','tool_schema_adherence','long_horizon_stop','constraint_retention','failure_recovery','cost_measurement')) {
    if ([string]$model.evaluation.$field -notin @('passed','measured')) { [void]$issues.Add("evaluation_$field`_incomplete") }
  }
  if ([string]$request.risk_level -eq 'L4' -and [string]::IsNullOrWhiteSpace([string]$request.human_approval_ref)) { [void]$issues.Add('L4_human_approval_required') }
}
$fallback = $null
if ($null -ne $model -and -not [string]::IsNullOrWhiteSpace([string]$model.fallback_model_id)) { $fallback = [string]$model.fallback_model_id }
$result = [ordered]@{
  status = if ($issues.Count -eq 0) { 'route_plan_ready' } elseif ($issues -contains 'model_not_production_approved' -and $null -ne $fallback) { 'shadow_only_fallback_required' } else { 'route_denied' }
  task_id = [string]$request.task_id; model_id = [string]$request.model_id; model_version = [string]$request.model_version
  provider_id = if ($null -ne $model) { [string]$model.provider_id } else { $null }
  fallback_model_id = $fallback; issues = @($issues); dispatch_authority = 'none'
  dispatch_enabled = [bool]$registry.network_dispatch_enabled
  external_call_made = $false; tools_authorized = $false; data_scope_expanded = $false; execution_authorized = $false
}
if ($PassThru) { $result | ConvertTo-Json -Depth 10 } else { [PSCustomObject]$result | Format-List }
if ($result.status -eq 'route_denied') { exit 1 }
