<#
.SYNOPSIS
  Validates a declarative enterprise change plan without executing it.
.DESCRIPTION
  The gate parses one structured plan, checks evidence and authority boundaries,
  and returns a review status. It never starts a process, opens a listener,
  accesses the network, writes a business system, or grants authority.
#>
param(
  [ValidateSet('Plan', 'Execute')][string]$Phase = 'Plan',
  [string]$RequestPath = '',
  [string]$RequestJson = '',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$reasons = [System.Collections.Generic.List[string]]::new()

if ([string]::IsNullOrWhiteSpace($RequestPath) -eq [string]::IsNullOrWhiteSpace($RequestJson)) {
  throw 'Provide exactly one of RequestPath or RequestJson.'
}
if (-not [string]::IsNullOrWhiteSpace($RequestPath)) {
  if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) { throw 'RequestPath does not exist.' }
  $RequestJson = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8
}
$request = $RequestJson | ConvertFrom-Json

function Require-Value([string]$Name, $Value) {
  if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
    [void]$reasons.Add("missing_$Name")
  }
}
function Require-Items([string]$Name, $Value) {
  if ($null -eq $Value -or @($Value).Count -eq 0) { [void]$reasons.Add("missing_$Name") }
}

foreach ($field in @('plan_id', 'plan_version', 'task_id', 'workflow_id', 'workflow_version', 'policy_version', 'domain', 'risk_level')) {
  Require-Value $field $request.$field
}
if ($request.risk_level -notin @('L1', 'L2', 'L3', 'L4')) { [void]$reasons.Add('unsupported_risk_level') }
if ($request.domain -notin @('governance_policy', 'listing_growth', 'advertising', 'profitability', 'inventory', 'procurement_logistics')) { [void]$reasons.Add('unsupported_domain') }

foreach ($field in @('snapshot_id', 'snapshot_hash', 'observed_at', 'data_time_range')) { Require-Value "current_state_$field" $request.current_state.$field }
Require-Items 'current_state_source_refs' $request.current_state.source_refs
if ($request.current_state.snapshot_hash -notmatch '^sha256:[a-fA-F0-9]{64}$') { [void]$reasons.Add('invalid_current_state_snapshot_hash') }

foreach ($field in @('target_id', 'target_version')) { Require-Value "desired_state_$field" $request.desired_state.$field }
Require-Items 'desired_state_constraints' $request.desired_state.constraints
Require-Items 'desired_state_success_criteria' $request.desired_state.success_criteria

Require-Items 'diff' $request.diff
foreach ($item in @($request.diff)) {
  foreach ($field in @('diff_id', 'field', 'candidate_action', 'risk_level')) { Require-Value "diff_$field" $item.$field }
  Require-Items "diff_$($item.diff_id)_evidence_refs" $item.evidence_refs
  if ($null -eq $item.reversible) { [void]$reasons.Add("diff_$($item.diff_id)_reversibility_required") }
  if ($item.risk_level -eq 'L4' -and -not $item.reversible) { [void]$reasons.Add("diff_$($item.diff_id)_L4_rollback_required") }
}

Require-Items 'plan_preview_steps' $request.plan_preview.steps
foreach ($step in @($request.plan_preview.steps)) {
  foreach ($field in @('step_id', 'action_class', 'expected_effect')) { Require-Value "plan_step_$field" $step.$field }
  Require-Items "plan_step_$($step.step_id)_diff_refs" $step.diff_refs
  Require-Items "plan_step_$($step.step_id)_verification_method" $step.verification_method
  Require-Items "plan_step_$($step.step_id)_stop_conditions" $step.stop_conditions
  if ($step.action_class -eq 'external_write' -and $request.risk_level -ne 'L4') { [void]$reasons.Add('external_write_must_be_L4') }
}

Require-Items 'evidence_pack_source_refs' $request.evidence_pack.source_refs
foreach ($field in @('data_time_range', 'formula_or_method_ref', 'artifact_hash')) { Require-Value "evidence_pack_$field" $request.evidence_pack.$field }
if ($request.evidence_pack.artifact_hash -notmatch '^sha256:[a-fA-F0-9]{64}$') { [void]$reasons.Add('invalid_evidence_pack_artifact_hash') }
if ($null -eq $request.evidence_pack.assumptions) { [void]$reasons.Add('missing_evidence_pack_assumptions') }
if ($null -eq $request.evidence_pack.pending_verification) { [void]$reasons.Add('missing_evidence_pack_pending_verification') }

Require-Value 'verification_producer_id' $request.verification.producer_id
Require-Value 'verification_independent_verifier_id' $request.verification.independent_verifier_id
Require-Value 'verification_result_status' $request.verification.result_status
if ($request.verification.producer_id -eq $request.verification.independent_verifier_id) { [void]$reasons.Add('self_verification_denied') }
if ($request.verification.replayable -ne $true) { [void]$reasons.Add('replayability_required') }

if ($request.execution.authorized -eq $true) { [void]$reasons.Add('plan_cannot_grant_execution') }
if ($request.execution.external_write -eq $true) { [void]$reasons.Add('external_write_disabled_this_release') }
if ($Phase -eq 'Execute') { [void]$reasons.Add('execute_disabled_this_release') }

$status = 'blocked'
$nextStep = 'freeze_preserve_evidence_and_return_to_broker'
if ($reasons.Count -eq 0) {
  if ($request.risk_level -eq 'L4' -or @($request.diff | Where-Object { $_.risk_level -eq 'L4' }).Count -gt 0) {
    $status = 'needs_human'
    $nextStep = 'human_review_of_candidate_plan_no_execution'
  } else {
    $status = 'plan_valid'
    $nextStep = 'broker_review_no_execution'
  }
}

$result = [PSCustomObject]@{
  status = $status
  phase = $Phase
  plan_id = $request.plan_id
  task_id = $request.task_id
  risk_level = $request.risk_level
  plan_authorized = ($status -in @('plan_valid', 'needs_human'))
  execution_authorized = $false
  adoption_authority = 'none'
  process_started = $false
  listeners_opened = $false
  external_calls = $false
  files_written = $false
  permissions_granted = $false
  immutable_receipt_required = $true
  next_step = $nextStep
  reasons = @($reasons)
}
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { $result | Format-List }
if ($status -eq 'blocked') { exit 1 }