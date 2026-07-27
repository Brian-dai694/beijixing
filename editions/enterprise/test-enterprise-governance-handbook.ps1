param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'enterprise-governance-handbook-policy.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$index = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'governance-handbook-index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$sync = Join-Path $PSScriptRoot 'sync-enterprise-governance-handbook.ps1'
$plan = Join-Path $PSScriptRoot 'new-enterprise-handbook-change-plan.ps1'
$verify = Join-Path $PSScriptRoot 'verify-enterprise-handbook-change-plan.ps1'
function Run([string]$Script, [string[]]$Arguments) { $raw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1); [pscustomobject]@{ code = $LASTEXITCODE; text = (($raw | ForEach-Object { $_.ToString() }) -join "`n") } }
$cases = [System.Collections.Generic.List[object]]::new()
$cases.Add([pscustomobject]@{ name = 'progressive_disclosure_is_defined'; passed = (@($policy.progressive_disclosure).Count -eq 4 -and @($policy.progressive_disclosure) -contains 'implementation_and_state') })
$cases.Add([pscustomobject]@{ name = 'behavior_cards_are_indexed'; passed = (@($index.cards).Count -ge 2 -and $index.execution_authority -eq $false) })
$syncRun = Run $sync @('-PassThru')
$cases.Add([pscustomobject]@{ name = 'sync_reads_real_sources_and_writes_manifest'; passed = ($syncRun.code -eq 0 -and $syncRun.text -match 'sha256:' -and $syncRun.text -match 'execution_authority.*false') })
$planRun = Run $plan @('-BehaviorId', 'sensitive-data-export', '-ChangeSummary', 'extend export approval to customer data', '-DeclaredDiffRef', 'sha256:diff', '-TaskId', 'task_handbook_1', '-GrantId', 'grant_handbook_1', '-TraceId', 'trace_handbook_1', '-PassThru')
$cases.Add([pscustomobject]@{ name = 'change_plan_is_behavior_scoped_and_nonexecuting'; passed = ($planRun.code -eq 0 -and $planRun.text -match 'plan_only.*true' -and $planRun.text -match 'requires_approval.*true') })
$planPath = if ($planRun.code -eq 0) { ($planRun.text | ConvertFrom-Json).plan_path } else { '' }
$freshRun = Run $verify @('-PlanPath', $planPath, '-PassThru')
$cases.Add([pscustomobject]@{ name = 'unchanged_sources_are_fresh_before_approval'; passed = ($freshRun.code -eq 0 -and $freshRun.text -match 'source_fresh.*true' -and $freshRun.text -match 'execution_authority.*false') })
if ($planPath) {
  $tampered = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $tampered.source_snapshot[0].sha256 = 'sha256:' + ('0' * 64)
  [IO.File]::WriteAllText($planPath, ($tampered | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
}
$driftRun = Run $verify @('-PlanPath', $planPath, '-PassThru')
$cases.Add([pscustomobject]@{ name = 'source_drift_blocks_approval'; passed = ($driftRun.code -ne 0 -and $driftRun.text -match 'handbook_plan_source_drift' -and $driftRun.text -match 'approval_allowed.*false') })
$failed = @($cases | Where-Object { -not $_.passed })
$out = [pscustomobject]@{ passed = ($failed.Count -eq 0); cases = @($cases); execution_authority = $false; production_writes = $false; external_calls = $false }
if ($PassThru) { $out | ConvertTo-Json -Depth 10 } else { $cases | Format-Table -AutoSize }
if ($failed.Count) { throw ('Enterprise governance handbook regression failed: ' + (($failed.name) -join ', ')) }
