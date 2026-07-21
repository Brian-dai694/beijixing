<#
.SYNOPSIS
  Admits a scanned OneSkills proposal or evaluates an executor Work Order candidate.
.DESCRIPTION
  This gate never installs OneSkills, starts FastMCP, opens a listener, or executes
  a Work Order. It consumes references to admission evidence produced by the
  enterprise Skill Intake Gate and returns a broker decision only.
#>
param(
  [ValidateSet('resource_proposal', 'expert_proposal', 'executor')]
  [string]$Mode,
  [ValidateSet('L0', 'L1', 'L2', 'L3', 'L4')]
  [string]$TaskLevel,
  [string]$TaskId = '',
  [string]$GrantId = '',
  [string]$WorkOrderId = '',
  [string]$AdmissionEvidenceRef = '',
  [ValidateSet('approved', 'conditional', 'denied')]
  [string]$AdmissionDecision = 'denied',
  [ValidateSet('none', 'stdio', 'http', 'streamable_http')]
  [string]$Transport = 'none',
  [ValidateSet('public', 'internal_sanitized', 'confidential_reference_only', 'restricted_secret')]
  [string]$DataClassification = 'public',
  [switch]$SanitizedEvidencePack,
  [switch]$ActiveTaskGrant,
  [switch]$HumanApproval,
  [switch]$PreflightEvidence,
  [switch]$IndependentVerifier,
  [switch]$VerifiedRunnerAttestation,
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$reasons = [System.Collections.Generic.List[string]]::new()
foreach ($field in @(
  @{ name = 'task_id'; value = $TaskId },
  @{ name = 'grant_id'; value = $GrantId },
  @{ name = 'admission_evidence_ref'; value = $AdmissionEvidenceRef }
)) {
  if ([string]::IsNullOrWhiteSpace($field.value)) { [void]$reasons.Add("missing_$($field.name)") }
}
if ($AdmissionDecision -eq 'denied') { [void]$reasons.Add('skill_intake_admission_denied') }
if ($Transport -in @('http', 'streamable_http')) { [void]$reasons.Add('fastmcp_http_transport_disabled') }
if ($DataClassification -in @('confidential_reference_only', 'restricted_secret')) { [void]$reasons.Add('raw_sensitive_data_not_admissible') }
if (-not $SanitizedEvidencePack) { [void]$reasons.Add('sanitized_evidence_pack_required') }
if (-not $ActiveTaskGrant) { [void]$reasons.Add('active_task_grant_required') }

$status = 'blocked'
$nextStep = 'freeze_and_preserve_admission_evidence'
if ($Mode -in @('resource_proposal', 'expert_proposal')) {
  if ($TaskLevel -notin @('L2', 'L3')) { [void]$reasons.Add('proposal_requires_L2_or_L3') }
  if ($reasons.Count -eq 0) {
    $status = 'proposal_admitted'
    $nextStep = 'broker_may_request_structured_proposal_and_receipt'
  }
} elseif ($Mode -eq 'executor') {
  if ([string]::IsNullOrWhiteSpace($WorkOrderId)) { [void]$reasons.Add('missing_work_order_id') }
  if ($TaskLevel -ne 'L4') { [void]$reasons.Add('executor_requires_L4') }
  if (-not $HumanApproval) { [void]$reasons.Add('explicit_human_approval_required') }
  if (-not $PreflightEvidence) { [void]$reasons.Add('preflight_evidence_required') }
  if (-not $IndependentVerifier) { [void]$reasons.Add('independent_verifier_required') }
  if (-not $VerifiedRunnerAttestation) { [void]$reasons.Add('verified_runner_attestation_required') }
  if ($reasons.Count -eq 0) {
    $status = 'conditional'
    $nextStep = 'broker_must_issue_dedicated_runner_dispatch_decision'
  }
}

$result = [PSCustomObject]@{
  status = $status
  mode = $Mode
  task_level = $TaskLevel
  task_id = $TaskId
  grant_id = $GrantId
  work_order_id = $WorkOrderId
  admission_evidence_ref = $AdmissionEvidenceRef
  transport = $Transport
  proposal_only = ($Mode -in @('resource_proposal', 'expert_proposal'))
  execution_authorized = $false
  listeners_opened = $false
  processes_started = $false
  external_calls = $false
  permissions_granted = $false
  receipt_required = $true
  next_step = $nextStep
  reasons = @($reasons)
}
if ($PassThru) { $result | ConvertTo-Json -Depth 6 } else { $result | Format-List }
if ($status -eq 'blocked') { exit 1 }
