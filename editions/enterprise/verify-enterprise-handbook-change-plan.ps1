param(
  [Parameter(Mandatory = $true)][string]$PlanPath,
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$planRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-handbook/plans')) + [IO.Path]::DirectorySeparatorChar
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 12 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
try {
  $full = (Resolve-Path -LiteralPath $PlanPath -ErrorAction Stop).Path
  if (-not $full.StartsWith($planRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'outside' }
  $plan = Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  Emit ([ordered]@{ status = 'blocked'; reason = 'handbook_plan_invalid_or_outside_governed_root'; source_fresh = $false; execution_authority = $false }) 1
}
if ($plan.plan_only -ne $true -or $plan.execution_authority -ne $false -or $plan.source_freshness_required_before_approval -ne $true) { Emit ([ordered]@{ status = 'blocked'; reason = 'handbook_plan_authority_boundary_invalid'; source_fresh = $false; execution_authority = $false }) 1 }
if (@($plan.source_snapshot).Count -eq 0) { Emit ([ordered]@{ status = 'blocked'; reason = 'source_snapshot_required'; source_fresh = $false; execution_authority = $false }) 1 }
$drift = [System.Collections.Generic.List[object]]::new()
foreach ($source in @($plan.source_snapshot)) {
  $relative = [string]$source.path
  $sourceFull = [IO.Path]::GetFullPath((Join-Path $projectRoot ($relative -replace '/', '\')))
  if (-not $sourceFull.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) {
    $drift.Add([ordered]@{ path = $relative; reason = 'source_missing_or_outside_workspace' })
    continue
  }
  $actual = 'sha256:' + (Get-FileHash -LiteralPath $sourceFull -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne [string]$source.sha256) { $drift.Add([ordered]@{ path = $relative; reason = 'source_hash_drift'; expected = [string]$source.sha256; actual = $actual }) }
}
if ($drift.Count) { Emit ([ordered]@{ status = 'blocked'; reason = 'handbook_plan_source_drift'; plan_id = [string]$plan.plan_id; drift = @($drift); source_fresh = $false; approval_allowed = $false; execution_authority = $false }) 1 }
Emit ([ordered]@{ status = 'fresh'; plan_id = [string]$plan.plan_id; source_count = @($plan.source_snapshot).Count; source_fresh = $true; approval_allowed = $true; execution_authority = $false; process_started = $false })
