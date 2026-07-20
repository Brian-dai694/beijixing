param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$contract = Get-Content (Join-Path $root 'visible-execution-event-contract.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$templates = @(
  'deterministic-tool-eval.json',
  'on-demand-knowledge-eval.json',
  'independent-delegation-eval.json'
)
$cases = [System.Collections.Generic.List[object]]::new()
function Add-Case($Name, $Passed) {$cases.Add([PSCustomObject]@{name=$Name;passed=[bool]$Passed})}
foreach ($field in @('trace_id','parent_task_id','work_order_id','grant_id','actor_type','artifact_refs','status')) {
  Add-Case ("required_field_" + $field) (@($contract.required_fields) -contains $field)
}
foreach ($event in @('coordinator_started','child_work_order_created','child_grant_issued','tool_confirmation_required','disagreement_recorded','grant_revoked','result_completed','task_frozen')) {
  Add-Case ("visible_event_" + $event) (@($contract.allowed_events) -contains $event)
}
foreach ($field in @('raw_prompt','hidden_reasoning','credential_value','raw_private_content')) {
  Add-Case ("prohibited_" + $field) (@($contract.prohibited_payload_fields) -contains $field)
}
Add-Case 'append_only' ($contract.append_only -eq $true)
Add-Case 'coordinator_has_no_global_data' (@($contract.governance_invariants | Where-Object {$_ -match 'no global data'}).Count -eq 1)
Add-Case 'external_a2a_sanitized_only' (@($contract.governance_invariants | Where-Object {$_ -match 'sanitized Evidence Pack'}).Count -eq 1)
foreach ($name in $templates) {
  $template = Get-Content (Join-Path $root ('evaluation-templates\' + $name)) -Raw -Encoding UTF8 | ConvertFrom-Json
  Add-Case ("evaluation_template_" + $template.class) (@($template.required_checks).Count -ge 5 -and -not [string]::IsNullOrWhiteSpace($template.promotion_gate))
}
$failed=@($cases|Where-Object{-not $_.passed})
$result=[PSCustomObject]@{passed=($failed.Count -eq 0);cases=@($cases);external_calls=$false;production_authority='none'}
if($PassThru){$result|ConvertTo-Json -Depth 6}else{$cases|Format-Table -AutoSize}
if($failed.Count){throw ('Visible execution contract regression failed: '+($failed.name -join ', '))}
