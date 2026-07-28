<##
.SYNOPSIS
  Offline regression for model admission and governed routing.
##>
param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$gate = Join-Path $PSScriptRoot 'invoke-enterprise-model-route-gate.ps1'
$registry = Join-Path $PSScriptRoot 'model-registry.example.json'
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'beijixing-enterprise-model-route'
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
function Run([string]$Name, [string]$Model, [string]$Version, [string]$Risk, [string]$Data, [int]$Calls, [double]$Cost, [string]$Approval = '') {
  $path = Join-Path $tmp ($Name + '.json')
  [ordered]@{ task_id = 'task-' + $Name; model_id = $Model; model_version = $Version; risk_level = $Risk; data_classification = $Data; max_calls = $Calls; max_cost_usd = $Cost; max_latency_ms = 30000; human_approval_ref = $Approval } | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
  $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate -RequestPath $path -RegistryPath $registry -PassThru 2>&1)
  $code = $LASTEXITCODE; $value = $null; try { $value = ($out -join "`n") | ConvertFrom-Json } catch {}
  [PSCustomObject]@{ code = $code; value = $value }
}
$cases = [System.Collections.Generic.List[object]]::new()
$baseline = Run 'baseline' 'qwen-enterprise-readonly-v1' '1.0.0' 'L2' 'internal_sanitized' 3 0.10
$cases.Add([PSCustomObject]@{ name = 'approved_model_returns_plan_only'; passed = ($baseline.code -eq 0 -and $baseline.value.status -eq 'route_plan_ready' -and -not $baseline.value.execution_authorized -and -not $baseline.value.tools_authorized) })
$llada = Run 'llada' 'llada-2.2' '2.2' 'L2' 'internal_sanitized' 3 0.10
$cases.Add([PSCustomObject]@{ name = 'llada_candidate_requires_fallback'; passed = ($llada.code -eq 0 -and $llada.value.status -eq 'shadow_only_fallback_required' -and @($llada.value.issues) -contains 'model_not_production_approved' -and $llada.value.fallback_model_id -eq 'qwen-enterprise-readonly-v1') })
$unversioned = Run 'unversioned' 'qwen-enterprise-readonly-v1' 'must_be_pinned' 'L2' 'internal_sanitized' 3 0.10
$cases.Add([PSCustomObject]@{ name = 'unpinned_version_denied'; passed = ($unversioned.code -ne 0 -and @($unversioned.value.issues) -contains 'version_not_pinned') })
$budget = Run 'budget' 'qwen-enterprise-readonly-v1' '1.0.0' 'L2' 'internal_sanitized' 99 9.00
$cases.Add([PSCustomObject]@{ name = 'budget_excess_denied'; passed = ($budget.code -ne 0 -and @($budget.value.issues) -contains 'model_budget_exceeded') })
$l4 = Run 'l4' 'qwen-enterprise-readonly-v1' '1.0.0' 'L4' 'internal_sanitized' 3 0.10
$cases.Add([PSCustomObject]@{ name = 'l4_requires_human_approval'; passed = ($l4.code -ne 0 -and @($l4.value.issues) -contains 'L4_human_approval_required') })
$failed = @($cases | Where-Object { -not $_.passed })
$result = [PSCustomObject]@{ passed = ($failed.Count -eq 0); cases = @($cases); external_calls = $false; tools_authorized = $false; execution_authorized = $false }
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { $cases | Format-Table -AutoSize }
if ($failed.Count -gt 0) { throw ('Enterprise model route regression failed: ' + ($failed.name -join ', ')) }
