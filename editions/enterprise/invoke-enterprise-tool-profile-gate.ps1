<##
.SYNOPSIS
  Offline professional-tool Profile gate. It returns a bounded plan and
  never starts a tool, debugger, process, network listener, or provider.
##>
param(
  [ValidateSet('reverse-readonly','reverse-triage','reverse-edit','reverse-debug')][string]$Profile,
  [string]$Operation = '', [string]$TenantId = '', [string]$ProjectId = '', [string]$ArtifactId = '', [string]$ArtifactSha256 = '',
  [string]$SessionId = '', [string]$TaskId = '', [string]$GrantId = '', [string]$AgentId = '', [string]$AgentVersion = '', [string]$DeviceId = '',
  [string]$ToolId = '', [string]$ToolVersion = '', [string]$ToolManifestHash = '', [string]$ApprovalRef = '',
  [ValidateSet('missing','verified','expired','revoked')][string]$AttestationStatus = 'missing',
  [switch]$GrantActive, [switch]$BudgetAvailable, [switch]$IndependentEvidence, [switch]$HumanConfirmation,
  [switch]$PreflightSnapshot, [switch]$RollbackRef, [switch]$PostChangeVerification, [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tool-risk-policy.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$reasons = [System.Collections.Generic.List[string]]::new()
$profilePolicy = $policy.profiles.$Profile
$risk = if ($null -ne $profilePolicy) { [string]$profilePolicy.risk_level } else { '' }
if ($null -eq $profilePolicy) { [void]$reasons.Add('profile_not_registered') }
foreach ($item in @(@('tenant_id',$TenantId),@('project_id',$ProjectId),@('artifact_id',$ArtifactId),@('session_id',$SessionId),@('task_id',$TaskId),@('grant_id',$GrantId),@('agent_id',$AgentId),@('agent_version',$AgentVersion),@('device_id',$DeviceId),@('tool_id',$ToolId),@('tool_version',$ToolVersion),@('tool_manifest_hash',$ToolManifestHash),@('artifact_sha256',$ArtifactSha256))) { if ([string]::IsNullOrWhiteSpace([string]$item[1])) { [void]$reasons.Add("missing_$($item[0])") } }
if (@('current_project','current_database','last_artifact','default_session','all_projects','all_users') -contains $ProjectId -or @('current_project','current_database','last_artifact','default_session','all_projects','all_users') -contains $ArtifactId) { [void]$reasons.Add('implicit_resource_binding_denied') }
if (-not $GrantActive) { [void]$reasons.Add('active_task_grant_required') }
if (-not $BudgetAvailable) { [void]$reasons.Add('budget_required') }
if ($AttestationStatus -ne 'verified') { [void]$reasons.Add('verified_attestation_required') }
if ($null -ne $profilePolicy) {
  if (@($profilePolicy.allowed_operations) -notcontains $Operation) { [void]$reasons.Add('operation_not_allowed_by_profile') }
  if (@($profilePolicy.denied_operations) -contains $Operation) { [void]$reasons.Add('operation_explicitly_denied') }
  if ($risk -eq 'R1_analysis' -and -not $IndependentEvidence) { [void]$reasons.Add('independent_evidence_required') }
  if ($risk -eq 'R2_modify') {
    foreach ($item in @(@('approval_ref',$ApprovalRef),@('human_confirmation',$HumanConfirmation),@('preflight_snapshot',$PreflightSnapshot),@('rollback_ref',$RollbackRef),@('post_change_verification',$PostChangeVerification))) { if ((($item[1] -is [bool]) -and -not [bool]$item[1]) -or (($item[1] -is [string]) -and [string]::IsNullOrWhiteSpace([string]$item[1]))) { [void]$reasons.Add("$($item[0])_required_for_R2") } }
  }
  if ($risk -eq 'R3_execute_or_memory_write' -or $Profile -eq 'reverse-debug') { [void]$reasons.Add('R3_debug_and_memory_write_denied_current_release') }
}
$status = if ($reasons.Count -eq 0) { if ($risk -eq 'R2_modify') { 'needs_human_execution_confirmation' } else { 'tool_plan_allowed' } } else { 'blocked' }
$result = [ordered]@{
  status=$status; profile=$Profile; risk_level=$risk; operation=$Operation; tenant_id=$TenantId; project_id=$ProjectId; artifact_id=$ArtifactId; session_id=$SessionId; task_id=$TaskId; grant_id=$GrantId
  execution_authorized=$false; process_started=$false; debugger_started=$false; network_opened=$false; memory_written=$false; permissions_granted=$false
  max_calls=if($null -ne $profilePolicy){$profilePolicy.max_calls}else{0}; max_runtime_seconds=if($null -ne $profilePolicy){$profilePolicy.max_runtime_seconds}else{0}; max_output_bytes=if($null -ne $profilePolicy){$profilePolicy.max_output_bytes}else{0}
  evidence_receipt_required=$true; revoke_before_next_call=$true; reasons=@($reasons)
}
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { [PSCustomObject]$result | Format-List }
if ($status -eq 'blocked') { exit 1 }
