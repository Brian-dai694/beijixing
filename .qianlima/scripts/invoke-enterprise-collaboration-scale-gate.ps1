param(
  [Parameter(Mandatory)][string]$RequestPath,
  [Parameter(Mandatory)][string]$StatePath,
  [string]$ContractPath = '',
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($ContractPath)) { $ContractPath = Join-Path $root 'enterprise-collaboration-scale-contract.json' }
$contract = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
$violations = [System.Collections.Generic.List[string]]::new()
$pauses = [System.Collections.Generic.List[string]]::new()
function Missing($Value) {
  if ($null -eq $Value) { return $true }
  if ($Value -is [System.Array]) { return ($Value.Count -eq 0) }
  return [string]::IsNullOrWhiteSpace([string]$Value)
}
function FieldValue($Object, [string]$Name) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

foreach ($field in $contract.required_request_fields) {
  if (Missing (FieldValue $request $field)) { [void]$violations.Add("missing_$field") }
}
$participants = @($request.participants)
if ($participants.Count -lt 1) { [void]$violations.Add('participants_required') }
$now = [DateTimeOffset]::UtcNow
$workOrders = [System.Collections.Generic.List[string]]::new()
$grants = [System.Collections.Generic.List[string]]::new()
$employeeCounts = @{}
foreach ($p in $participants) {
  foreach ($field in $contract.participant_required_fields) {
    if (Missing (FieldValue $p $field)) { [void]$violations.Add("participant_${field}_required") }
  }
  if (-not (Missing $p.work_order_id)) { [void]$workOrders.Add([string]$p.work_order_id) }
  if (-not (Missing $p.grant_id)) { [void]$grants.Add([string]$p.grant_id) }
  if (-not (Missing $p.employee_id)) {
    $key = [string]$p.employee_id
    if (-not $employeeCounts.ContainsKey($key)) { $employeeCounts[$key] = 0 }
    $employeeCounts[$key]++
  }
  if ([string]$p.grant_status -ne 'issued') { [void]$violations.Add('participant_grant_not_issued') }
  if ([string]$p.grant_task_id -ne [string]$request.task_id) { [void]$violations.Add('grant_task_binding_mismatch') }
  if ([string]$p.grant_employee_id -ne [string]$p.employee_id) { [void]$violations.Add('grant_employee_binding_mismatch') }
  if ([string]$p.grant_agent_id -ne [string]$p.agent_id) { [void]$violations.Add('grant_agent_binding_mismatch') }
  if ([string]$p.grant_department_id -ne [string]$request.department_id) { [void]$violations.Add('grant_department_binding_mismatch') }
  if ($p.can_delegate -ne $false) { [void]$violations.Add('participant_secondary_delegation_denied') }
  if (@($p.allowed_tools).Count -lt 1) { [void]$violations.Add('minimum_tool_scope_required') }
  try { if ([DateTimeOffset]::Parse([string]$p.grant_expires_at) -le $now) { [void]$violations.Add('participant_grant_expired') } } catch { [void]$violations.Add('participant_grant_expiry_invalid') }
  if ([string]$p.data_classification -notin @('public','internal_sanitized','confidential_reference_only')) { [void]$violations.Add('participant_data_classification_denied') }
  if ([string]$p.evidence_pack_ref -notmatch '^evidence-pack:') { [void]$violations.Add('minimum_evidence_pack_required') }
}
if (@($workOrders | Sort-Object -Unique).Count -ne $workOrders.Count) { [void]$violations.Add('shared_work_order_denied') }
if (@($grants | Sort-Object -Unique).Count -ne $grants.Count) { [void]$violations.Add('shared_grant_denied') }
if ([string]$request.direct_agent_to_agent -ne 'deny') { [void]$violations.Add('direct_agent_to_agent_denied') }
if ([string]$request.status -in @('cancelled','frozen','revoked','completed')) { [void]$violations.Add('terminal_collaboration_cannot_admit_new_work') }

$risk = [string]$request.risk_level
$roles = @($participants.role)
function Validate-Approval($Approval, $RequiredFields, $AllowedRoles, [string]$Prefix) {
  if ($null -eq $Approval) { [void]$violations.Add("${Prefix}_approval_required"); return }
  foreach ($field in $RequiredFields) { if (Missing (FieldValue $Approval $field)) { [void]$violations.Add("${Prefix}_approval_${field}_required") } }
  if ([string]$Approval.approver_role -notin @($AllowedRoles)) { [void]$violations.Add("${Prefix}_approver_role_denied") }
  if ([string]$Approval.decision -ne 'approved') { [void]$violations.Add("${Prefix}_approval_not_approved") }
  foreach ($field in @('organization_id','department_id','project_id','task_id')) { if ([string]$Approval.$field -ne [string]$request.$field) { [void]$violations.Add("${Prefix}_approval_scope_mismatch") } }
  try { if ([DateTimeOffset]::Parse([string]$Approval.valid_from) -gt $now -or [DateTimeOffset]::Parse([string]$Approval.expires_at) -le $now) { [void]$violations.Add("${Prefix}_approval_not_active") } } catch { [void]$violations.Add("${Prefix}_approval_time_invalid") }
}
if ($risk -in @('L3','L4')) { Validate-Approval $request.manager_approval $contract.approval_evidence.manager_required_fields $contract.approval_evidence.manager_roles 'manager' }
if ($risk -in @('L3','L4') -and $roles -notcontains 'independent_verifier') { [void]$violations.Add('independent_verifier_required') }
if ($risk -eq 'L4') {
  Validate-Approval $request.human_approval $contract.approval_evidence.L4_human_required_fields @('department_manager','business_owner','security_admin','data_owner','technical_owner','finance_owner') 'human'
  $humanApprover = [string]$request.human_approval.approver_employee_id
  if (-not (Missing $humanApprover) -and ($humanApprover -eq [string]$request.coordinator_employee_id -or @($participants.employee_id) -contains $humanApprover)) { [void]$violations.Add('approver_must_be_distinct') }
  if ($request.candidate_only -ne $true) { [void]$violations.Add('L4_candidate_only_required') }
}

if ($null -ne $request.batch_approval) {
  $batch = $request.batch_approval
  if ([string]$batch.profile -notin @($contract.batch_approval.allowed_profiles)) { [void]$violations.Add('batch_approval_profile_denied') }
  foreach ($field in $contract.batch_approval.required_bindings) { if (Missing (FieldValue $batch $field)) { [void]$violations.Add("batch_${field}_required") } }
  foreach ($field in @('organization_id','department_id','project_id')) { if ([string]$batch.$field -ne [string]$request.$field) { [void]$violations.Add('batch_scope_mismatch') } }
  try {
    if ([DateTimeOffset]::Parse([string]$batch.valid_from) -gt $now -or [DateTimeOffset]::Parse([string]$batch.expires_at) -le $now) { [void]$violations.Add('batch_approval_not_active') }
  } catch { [void]$violations.Add('batch_approval_time_invalid') }
  if ([double]$batch.units_used + $participants.Count -gt [double]$batch.aggregate_limit) { [void]$violations.Add('batch_aggregate_limit_exceeded') }
}

$limits = $contract.limits
if ($participants.Count -gt [int]$limits.max_parallel_agents_per_task) { [void]$pauses.Add('task_concurrency_limit') }
foreach ($count in $employeeCounts.Values) { if ([int]$count -gt [int]$limits.max_parallel_agents_per_employee) { [void]$pauses.Add('employee_concurrency_limit') } }
if ([int]$state.department_active_agents + $participants.Count -gt [int]$limits.max_parallel_agents_per_department) { [void]$pauses.Add('department_concurrency_limit') }
if ([int]$state.organization_active_agents + $participants.Count -gt [int]$limits.max_parallel_agents_per_organization) { [void]$pauses.Add('organization_concurrency_limit') }
if ([int]$state.department_pending_verifications -ge [int]$limits.max_pending_verifications_per_department) { [void]$pauses.Add('verification_backpressure') }
if ($risk -in @('L3','L4') -and [int]$state.manager_pending_approvals -ge [int]$limits.max_pending_approvals_per_manager) { [void]$pauses.Add('approval_backpressure') }
if ($state.audit_available -ne $true) { if ($risk -in @('L3','L4')) { [void]$violations.Add('audit_required_for_high_risk') } else { [void]$pauses.Add('audit_unavailable') } }
if ([double]$request.requested_budget.cost_usd -gt [double]$state.department_remaining_budget_usd) { [void]$pauses.Add('department_budget_insufficient') }

$decision = if ($violations.Count) { 'rejected' } elseif ($pauses.Count) { 'paused' } else { 'admitted' }
$result = [ordered]@{
  decision = $decision
  collaboration_id = $request.collaboration_id
  violations = @($violations | Sort-Object -Unique)
  pause_reasons = @($pauses | Sort-Object -Unique)
  queue_key = "tenant:$($request.tenant_id)/department:$($request.department_id)/risk:$risk"
  revocation_manifest = [ordered]@{
    collaboration_id = $request.collaboration_id
    task_id = $request.task_id
    participant_grant_ids = @($grants)
    direct_mcp_session_refs = @($request.direct_mcp_session_refs)
    required_on = @('cancelled','employee_suspended','employee_transferred','employee_offboarded','grant_expired','policy_failed','budget_exhausted')
    order = @($contract.revocation_manifest.order)
  }
  grants_issued = $false
  execution_authorized = $false
  external_calls = $false
}
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { [PSCustomObject]$result | Format-List }
if ($decision -eq 'rejected') { exit 2 }
if ($decision -eq 'paused') { exit 3 }
