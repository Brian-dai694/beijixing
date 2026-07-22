<#
.SYNOPSIS
  Evaluates an Open Interpreter Plan or Execute request without starting it.
.DESCRIPTION
  This enterprise Overlay performs contract checks only. It never imports or
  launches Open Interpreter, opens a listener, runs code, or grants authority.
#>
param(
  [ValidateSet('Plan', 'Execute')][string]$Phase,
  [ValidateSet('L0', 'L1', 'L2', 'L3', 'L4')][string]$RiskLevel,
  [ValidateSet('csv_readonly_analysis', 'xlsx_readonly_analysis', 'python_bounded_compute', 'local_readonly_query', 'arbitrary_shell', 'package_install', 'browser_control', 'erp_write', 'advertising_write', 'file_delete')][string]$RequestedCapability,
  [ValidateSet('public', 'internal_sanitized', 'confidential_reference_only', 'restricted_secret')][string]$DataClassification = 'public',
  [string]$TaskId = '',
  [string]$WorkOrderId = '',
  [string]$WorkOrderTaskId = '',
  [string]$GrantId = '',
  [string]$GrantTaskId = '',
  [string]$AttestationId = '',
  [ValidateSet('none', 'allowlisted')][string]$NetworkAccess = 'none',
  [ValidateSet('none', 'task_workspace')][string]$WriteAccess = 'none',
  [switch]$AdapterAdmitted,
  [switch]$GrantActive,
  [switch]$AttestationVerified,
  [switch]$BudgetAvailable,
  [switch]$AuditSinkReady,
  [switch]$RevocationPathReady,
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$reasons = [System.Collections.Generic.List[string]]::new()
foreach ($field in @(
  @{ name = 'task_id'; value = $TaskId },
  @{ name = 'work_order_id'; value = $WorkOrderId },
  @{ name = 'work_order_task_id'; value = $WorkOrderTaskId },
  @{ name = 'grant_id'; value = $GrantId },
  @{ name = 'grant_task_id'; value = $GrantTaskId }
)) {
  if ([string]::IsNullOrWhiteSpace($field.value)) { [void]$reasons.Add("missing_$($field.name)") }
}
if (-not $AdapterAdmitted) { [void]$reasons.Add('adapter_admission_required') }
if (-not $GrantActive) { [void]$reasons.Add('active_task_grant_required') }
if (-not $BudgetAvailable) { [void]$reasons.Add('budget_required') }
if (-not $AuditSinkReady) { [void]$reasons.Add('audit_sink_required') }
if (-not $RevocationPathReady) { [void]$reasons.Add('revocation_path_required') }
if ($TaskId -ne $WorkOrderTaskId -or $TaskId -ne $GrantTaskId) { [void]$reasons.Add('task_binding_mismatch') }
if ($NetworkAccess -ne 'none') { [void]$reasons.Add('network_access_denied') }
if ($WriteAccess -ne 'none') { [void]$reasons.Add('write_access_denied_initial_release') }
if ($DataClassification -notin @('public', 'internal_sanitized')) { [void]$reasons.Add('data_classification_denied') }
if ($RequestedCapability -notin @('csv_readonly_analysis', 'xlsx_readonly_analysis', 'python_bounded_compute', 'local_readonly_query')) { [void]$reasons.Add('capability_not_in_initial_allowlist') }
if ($RiskLevel -notin @('L1', 'L2')) { [void]$reasons.Add('initial_release_limited_to_L1_L2') }

$status = 'blocked'
$nextStep = 'freeze_and_revoke'
if ($Phase -eq 'Plan') {
  if ($reasons.Count -eq 0) {
    $status = 'plan_allowed'
    $nextStep = 'return_structured_execution_plan_for_broker_review'
  }
} else {
  if ([string]::IsNullOrWhiteSpace($AttestationId)) { [void]$reasons.Add('sandbox_attestation_id_required') }
  if (-not $AttestationVerified) { [void]$reasons.Add('verified_sandbox_attestation_required') }
  [void]$reasons.Add('open_interpreter_execution_disabled_this_release')
}

$result = [PSCustomObject]@{
  status = $status
  phase = $Phase
  task_id = $TaskId
  work_order_id = $WorkOrderId
  grant_id = $GrantId
  requested_capability = $RequestedCapability
  risk_level = $RiskLevel
  plan_authorized = ($status -eq 'plan_allowed')
  execution_authorized = $false
  process_started = $false
  listeners_opened = $false
  network_opened = $false
  files_written = $false
  permissions_granted = $false
  receipt_required = $true
  next_step = $nextStep
  reasons = @($reasons)
}
if ($PassThru) { $result | ConvertTo-Json -Depth 6 } else { $result | Format-List }
if ($status -eq 'blocked') { exit 1 }
