<# .SYNOPSIS Offline regression for declarative enterprise change plans. #>
param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$contract = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'declarative-change-plan-contract.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$gate = Join-Path $PSScriptRoot 'invoke-declarative-change-plan-gate.ps1'
$hostPath = (Get-Process -Id $PID).Path
$cases = [System.Collections.Generic.List[object]]::new()
function Add-Case([string]$Name, [bool]$Passed) { $cases.Add([PSCustomObject]@{ name = $Name; passed = $Passed }) }
function New-Plan {
  [ordered]@{
    plan_id = 'plan-1'; plan_version = '1.0.0'; task_id = 'task-1'; workflow_id = 'listing-growth'; workflow_version = '2.0.0'; policy_version = '1.0.0'; domain = 'listing_growth'; risk_level = 'L2'
    current_state = [ordered]@{ snapshot_id = 'snapshot-1'; snapshot_hash = ('sha256:' + ('a' * 64)); observed_at = '2026-07-22T00:00:00Z'; source_refs = @('source-1'); data_time_range = '2026-07-01/2026-07-21' }
    desired_state = [ordered]@{ target_id = 'target-1'; target_version = '1.0.0'; constraints = @('verified_product_facts_only'); success_criteria = @('evidence_complete') }
    diff = @([ordered]@{ diff_id = 'diff-1'; field = 'title'; current_value = 'old'; desired_value = 'candidate'; evidence_refs = @('source-1'); candidate_action = 'prepare_listing_candidate'; risk_level = 'L2'; reversible = $true })
    plan_preview = [ordered]@{ steps = @([ordered]@{ step_id = 'step-1'; diff_refs = @('diff-1'); action_class = 'local_analysis'; expected_effect = 'produce_candidate_only'; verification_method = @('fact_check'); stop_conditions = @('missing_evidence') }) }
    evidence_pack = [ordered]@{ source_refs = @('source-1'); data_time_range = '2026-07-01/2026-07-21'; formula_or_method_ref = 'listing-method-v1'; assumptions = @(); pending_verification = @(); artifact_hash = ('sha256:' + ('b' * 64)) }
    verification = [ordered]@{ producer_id = 'worker-1'; independent_verifier_id = 'checker-1'; replayable = $true; result_status = 'pending' }
    execution = [ordered]@{ authorized = $false; external_write = $false }
  }
}
function Copy-Plan($Plan) { (($Plan | ConvertTo-Json -Depth 20) | ConvertFrom-Json) }
function Run-Gate($Plan, [string]$Phase = 'Plan') {
  $json = $Plan | ConvertTo-Json -Depth 20 -Compress
  $requestPath = Join-Path ([System.IO.Path]::GetTempPath()) ("beijixing-plan-" + [guid]::NewGuid().ToString('N') + '.json')
  [System.IO.File]::WriteAllText($requestPath, $json, [System.Text.UTF8Encoding]::new($false))
  $out = @(& $hostPath -NoProfile -File $gate -Phase $Phase -RequestPath $requestPath -PassThru 2>&1)
  $code = $LASTEXITCODE; Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue; $value = $null
  try { $value = ($out -join [Environment]::NewLine) | ConvertFrom-Json } catch {}
  [PSCustomObject]@{ code = $code; value = $value }
}

Add-Case 'contract_has_no_runtime_dependency' ($contract.design_sources.runtime_dependencies -eq 'none')
$valid = Run-Gate (New-Plan)
Add-Case 'L2_evidence_backed_plan_is_valid_without_execution' ($valid.code -eq 0 -and $valid.value.status -eq 'plan_valid' -and -not $valid.value.execution_authorized)
$missingSource = Copy-Plan (New-Plan); $missingSource.current_state.source_refs = @(); $blockedSource = Run-Gate $missingSource
Add-Case 'missing_current_source_is_blocked' ($blockedSource.code -ne 0 -and @($blockedSource.value.reasons) -contains 'missing_current_state_source_refs')
$missingMethod = Copy-Plan (New-Plan); $missingMethod.evidence_pack.formula_or_method_ref = ''; $blockedMethod = Run-Gate $missingMethod
Add-Case 'missing_formula_or_method_is_blocked' ($blockedMethod.code -ne 0 -and @($blockedMethod.value.reasons) -contains 'missing_evidence_pack_formula_or_method_ref')
$selfReview = Copy-Plan (New-Plan); $selfReview.verification.independent_verifier_id = 'worker-1'; $blockedReview = Run-Gate $selfReview
Add-Case 'self_verification_is_blocked' ($blockedReview.code -ne 0 -and @($blockedReview.value.reasons) -contains 'self_verification_denied')
$notReplayable = Copy-Plan (New-Plan); $notReplayable.verification.replayable = $false; $blockedReplay = Run-Gate $notReplayable
Add-Case 'non_replayable_plan_is_blocked' ($blockedReplay.code -ne 0 -and @($blockedReplay.value.reasons) -contains 'replayability_required')
$writeL2 = Copy-Plan (New-Plan); $writeL2.plan_preview.steps[0].action_class = 'external_write'; $blockedWrite = Run-Gate $writeL2
Add-Case 'external_write_cannot_be_hidden_in_L2' ($blockedWrite.code -ne 0 -and @($blockedWrite.value.reasons) -contains 'external_write_must_be_L4')
$l4 = Copy-Plan (New-Plan); $l4.risk_level = 'L4'; $l4.diff[0].risk_level = 'L4'; $l4.plan_preview.steps[0].action_class = 'external_write'; $human = Run-Gate $l4
Add-Case 'L4_plan_is_candidate_only_needs_human' ($human.code -eq 0 -and $human.value.status -eq 'needs_human' -and -not $human.value.execution_authorized -and $human.value.adoption_authority -eq 'none')
$executionClaim = Copy-Plan (New-Plan); $executionClaim.execution.authorized = $true; $blockedClaim = Run-Gate $executionClaim
Add-Case 'plan_cannot_claim_execution_authority' ($blockedClaim.code -ne 0 -and @($blockedClaim.value.reasons) -contains 'plan_cannot_grant_execution')
$execute = Run-Gate (New-Plan) 'Execute'
Add-Case 'execute_phase_is_mechanically_denied' ($execute.code -ne 0 -and @($execute.value.reasons) -contains 'execute_disabled_this_release' -and -not $execute.value.process_started)
$failed = @($cases | Where-Object { -not $_.passed })
$result = [PSCustomObject]@{ passed = ($failed.Count -eq 0); cases = @($cases); listeners_opened = $false; processes_started = $false; external_calls = $false; files_written = $false; permissions_granted = $false }
if ($PassThru) { $result | ConvertTo-Json -Depth 10 } else { $cases | Format-Table -AutoSize }
if ($failed.Count -gt 0) { throw "Declarative change plan regression failed: $($failed.name -join ', ')" }
