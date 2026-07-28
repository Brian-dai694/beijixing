<##
.SYNOPSIS
  Converts one diagnostic action card into an approved, non-executing Work Order preview.
.DESCRIPTION
  Approval is recorded as evidence. This script never calls an advertising API and
  never claims that a business write was executed.
##>
param(
  [Parameter(Mandatory=$true)][string]$DiagnosticPackPath,
  [Parameter(Mandatory=$true)][string]$GrantPath,
  [Parameter(Mandatory=$true)][string]$DiagnosticReceiptPath,
  [Parameter(Mandatory=$true)][string]$VerificationReceiptPath,
  [int]$ActionCardIndex = 0,
  [Parameter(Mandatory=$true)][string]$RequesterId,
  [Parameter(Mandatory=$true)][string]$ApproverId,
  [Parameter(Mandatory=$true)][string]$ConfirmationId,
  [Parameter(Mandatory=$true)][string]$TenantId,
  [Parameter(Mandatory=$true)][string]$OrganizationId,
  [Parameter(Mandatory=$true)][string]$EmployeeId,
  [Parameter(Mandatory=$true)][string]$DeviceId,
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [Parameter(Mandatory=$true)][string]$CostCenter,
  [Parameter(Mandatory=$true)][string]$VerifierId,
  [Parameter(Mandatory=$true)][string]$ApproverRole,
  [Parameter(Mandatory=$true)][double]$BeforeBid,
  [Parameter(Mandatory=$true)][double]$BeforeBudget,
  [string]$OutputPath = '',
  [switch]$Confirmed,
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$powerShellResolver=Join-Path $PSScriptRoot 'resolve-enterprise-powershell.ps1';. $powerShellResolver;$powerShellCommand=Get-EnterprisePowerShellCommand
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$receiptRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\enterprise-receipts')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$grantRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\delegation-grants')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$workOrderRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\enterprise-work-orders')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$revocationPath=Join-Path $projectRoot '.qianlima\run-traces\grant-revocations.jsonl'
function Emit([hashtable]$Value, [int]$Code = 0) {
  if ($PassThru) { $Value | ConvertTo-Json -Depth 12 } else { $Value | Format-List }
  if ($Code -ne 0) { exit $Code }
}
function Get-DiagnosticResultHash([object]$Diagnostic) {
  $cards = @($Diagnostic.action_cards | ForEach-Object {
    @($_.campaign_id, $_.target_id, $_.issue, $_.recommendation, $_.evidence.source_hash, $_.evidence.data_as_of) -join '|'
  } | Sort-Object)
  $canonical = @("task_id=$($Diagnostic.task_id)", "grant_id=$($Diagnostic.grant_id)", "status=$($Diagnostic.status)", "source_hash=$($Diagnostic.source_hash)", "data_as_of=$($Diagnostic.data_as_of)", 'cards=', ($cards -join "`n")) -join "`n"
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
if (-not (Test-Path -LiteralPath $DiagnosticPackPath -PathType Leaf)) { Emit ([ordered]@{status='blocked';reason='diagnostic_pack_not_found';execution_authorized=$false}) 1 }
try { $pack = Get-Content -LiteralPath $DiagnosticPackPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Emit ([ordered]@{status='blocked';reason='diagnostic_pack_invalid';execution_authorized=$false}) 1 }
try { $grantFull=(Resolve-Path -LiteralPath $GrantPath -ErrorAction Stop).Path } catch { Emit ([ordered]@{status='blocked';reason='grant_not_found';execution_authorized=$false}) 1 }
if (-not $grantFull.StartsWith($grantRoot,[StringComparison]::OrdinalIgnoreCase)) { Emit ([ordered]@{status='blocked';reason='grant_outside_governed_root';execution_authorized=$false}) 1 }
try { $grant=Get-Content -LiteralPath $grantFull -Raw -Encoding UTF8|ConvertFrom-Json } catch { Emit ([ordered]@{status='blocked';reason='grant_invalid';execution_authorized=$false}) 1 }
if ([string]$grant.status -ne 'issued') { Emit ([ordered]@{status='blocked';reason='grant_not_issued';execution_authorized=$false}) 1 }
try { if ([DateTime]::Parse([string]$grant.expires_at).ToUniversalTime() -le [DateTime]::UtcNow) { Emit ([ordered]@{status='blocked';reason='grant_expired';execution_authorized=$false}) 1 } } catch { Emit ([ordered]@{status='blocked';reason='grant_expiry_invalid';execution_authorized=$false}) 1 }
if (Test-Path -LiteralPath $revocationPath -PathType Leaf) {
  try { $revoked=@(Get-Content -LiteralPath $revocationPath -Encoding UTF8|ForEach-Object{if(-not[string]::IsNullOrWhiteSpace($_)){$_|ConvertFrom-Json}}|Where-Object{$_.grant_id-eq[string]$grant.grant_id}) } catch { Emit ([ordered]@{status='blocked';reason='grant_revocation_ledger_invalid';execution_authorized=$false}) 1 }
  if (@($revoked).Count -gt 0) { Emit ([ordered]@{status='blocked';reason='grant_revoked';execution_authorized=$false}) 1 }
}
if ([string]::IsNullOrWhiteSpace($DiagnosticReceiptPath) -or [string]::IsNullOrWhiteSpace($VerificationReceiptPath)) { Emit ([ordered]@{status='blocked';reason='diagnostic_and_verification_receipts_required';execution_authorized=$false}) 1 }
try { $diagnosticReceiptFull=(Resolve-Path -LiteralPath $DiagnosticReceiptPath -ErrorAction Stop).Path; $verificationReceiptFull=(Resolve-Path -LiteralPath $VerificationReceiptPath -ErrorAction Stop).Path } catch { Emit ([ordered]@{status='blocked';reason='evidence_receipt_not_found';execution_authorized=$false}) 1 }
if (-not $diagnosticReceiptFull.StartsWith($receiptRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $verificationReceiptFull.StartsWith($receiptRoot,[StringComparison]::OrdinalIgnoreCase)) { Emit ([ordered]@{status='blocked';reason='evidence_receipt_outside_governed_root';execution_authorized=$false}) 1 }
try { $diagnosticReceipt=Get-Content -LiteralPath $diagnosticReceiptFull -Raw -Encoding UTF8|ConvertFrom-Json; $verificationReceipt=Get-Content -LiteralPath $verificationReceiptFull -Raw -Encoding UTF8|ConvertFrom-Json } catch { Emit ([ordered]@{status='blocked';reason='evidence_receipt_invalid';execution_authorized=$false}) 1 }
if ([string]$pack.status -ne 'review_required') { Emit ([ordered]@{status='blocked';reason='diagnostic_pack_not_review_required';execution_authorized=$false}) 1 }
if ($pack.dispatch_ready -ne $false -or $pack.write_performed -ne $false) { Emit ([ordered]@{status='blocked';reason='diagnostic_pack_write_boundary_failed';execution_authorized=$false}) 1 }
if ([string]$diagnosticReceipt.receipt_type -ne 'enterprise_readonly_diagnostic' -or [string]$verificationReceipt.receipt_type -ne 'independent_verification_receipt') { Emit ([ordered]@{status='blocked';reason='evidence_receipt_type_mismatch';execution_authorized=$false}) 1 }
if ([string]$pack.task_id -ne [string]$diagnosticReceipt.task_id -or [string]$pack.grant_id -ne [string]$diagnosticReceipt.grant_id) { Emit ([ordered]@{status='blocked';reason='diagnostic_receipt_binding_mismatch';execution_authorized=$false}) 1 }
if ([string]$verificationReceipt.parent_receipt_id -ne [string]$diagnosticReceipt.receipt_id -or [string]$verificationReceipt.task_id -ne [string]$pack.task_id -or [string]$verificationReceipt.grant_id -ne [string]$pack.grant_id) { Emit ([ordered]@{status='blocked';reason='verification_receipt_binding_mismatch';execution_authorized=$false}) 1 }
if ([string]$pack.source_hash -ne [string]$diagnosticReceipt.source_hash -or [string]$verificationReceipt.source_hash -ne [string]$diagnosticReceipt.source_hash) { Emit ([ordered]@{status='blocked';reason='evidence_source_hash_mismatch';execution_authorized=$false}) 1 }
if ([string]$verificationReceipt.verification_status -ne 'passed' -or $verificationReceipt.independent_verification -ne $true) { Emit ([ordered]@{status='blocked';reason='independent_verification_required';execution_authorized=$false}) 1 }
if ([string]$VerifierId -ne [string]$verificationReceipt.verifier_id) { Emit ([ordered]@{status='blocked';reason='verifier_identity_mismatch';execution_authorized=$false}) 1 }
if ([string]$grant.grant_id -ne [string]$pack.grant_id -or [string]$grant.task_id -ne [string]$pack.task_id) { Emit ([ordered]@{status='blocked';reason='grant_work_order_binding_mismatch';execution_authorized=$false}) 1 }
if ([string]$grant.tenant_id -ne $TenantId -or [string]$grant.organization_id -ne $OrganizationId -or [string]$grant.employee_id -ne $EmployeeId -or [string]$grant.device_id -ne $DeviceId -or [string]$grant.project_id -ne $ProjectId -or [string]$grant.cost_center -ne $CostCenter -or $RequesterId -ne $EmployeeId) { Emit ([ordered]@{status='blocked';reason='grant_identity_scope_mismatch';execution_authorized=$false}) 1 }
if ([string]$diagnosticReceipt.tenant_id -ne $TenantId -or [string]$diagnosticReceipt.organization_id -ne $OrganizationId -or [string]$diagnosticReceipt.employee_id -ne $EmployeeId -or [string]$diagnosticReceipt.device_id -ne $DeviceId -or [string]$diagnosticReceipt.project_id -ne $ProjectId) { Emit ([ordered]@{status='blocked';reason='diagnostic_receipt_identity_scope_mismatch';execution_authorized=$false}) 1 }
$packResultHash = Get-DiagnosticResultHash $pack
if ([string]::IsNullOrWhiteSpace([string]$diagnosticReceipt.diagnostic_result_hash) -or $packResultHash -ne [string]$diagnosticReceipt.diagnostic_result_hash) { Emit ([ordered]@{status='blocked';reason='diagnostic_result_hash_mismatch';execution_authorized=$false}) 1 }
$cards = @($pack.action_cards)
if ($ActionCardIndex -lt 0 -or $ActionCardIndex -ge $cards.Count) { Emit ([ordered]@{status='blocked';reason='action_card_not_found';execution_authorized=$false}) 1 }
if ([string]::IsNullOrWhiteSpace($RequesterId) -or [string]::IsNullOrWhiteSpace($ApproverId) -or $RequesterId -eq $ApproverId) { Emit ([ordered]@{status='blocked';reason='distinct_requester_and_approver_required';execution_authorized=$false}) 1 }
if (-not $Confirmed) { Emit ([ordered]@{status='awaiting_human_confirmation';reason='explicit_confirmation_required';execution_authorized=$false}) 1 }
if ([string]::IsNullOrWhiteSpace($ConfirmationId)) { Emit ([ordered]@{status='blocked';reason='confirmation_id_required';execution_authorized=$false}) 1 }
$packHash = (Get-FileHash -LiteralPath $DiagnosticPackPath -Algorithm SHA256).Hash.ToLowerInvariant()
$taskGate = Join-Path $PSScriptRoot 'invoke-enterprise-task-gate.ps1'
$gateOutput = @(& $powerShellCommand -NoProfile -ExecutionPolicy Bypass -File $taskGate -RequestedLevel L4 -DataClassification internal_sanitized -OrganizationalScope project -ActionType business_write -ApprovalProfile routine_reversible -TenantId $TenantId -OrganizationId $OrganizationId -EmployeeId $EmployeeId -DeviceId $DeviceId -ProjectId $ProjectId -CostCenter $CostCenter -AgentTrust T3 -GrantId ([string]$pack.grant_id) -AttestationStatus verified -VerifierId $VerifierId -HumanOwnerId $ApproverId -ApproverIds $ApproverId -ApproverRoles $ApproverRole -SnapshotRef ('snapshot:' + $packHash) -RollbackRef ('rollback:' + $packHash) -PassThru 2>&1)
$gate = $null; try { $gate = ($gateOutput -join "`n") | ConvertFrom-Json } catch { Emit ([ordered]@{status='blocked';reason='task_gate_invalid_response';execution_authorized=$false}) 1 }
if ($LASTEXITCODE -ne 0 -or $null -eq $gate -or $gate.status -ne 'allowed') { Emit ([ordered]@{status='blocked';reason='enterprise_task_gate_denied';task_gate=$gate;execution_authorized=$false}) 1 }
$card = $cards[$ActionCardIndex]
$workOrderId = 'wo-ad-diagnostic-' + ([guid]::NewGuid().ToString('N'))
$receipt = [ordered]@{
  receipt_id = 'receipt-' + $workOrderId
  receipt_type = 'approval_preview'
  task_id = [string]$pack.task_id
  grant_id = [string]$pack.grant_id
  source_refs = @('diagnostic_pack:' + $packHash)
  diagnostic_receipt_ref = 'receipt:' + [string]$diagnosticReceipt.receipt_id
  verification_receipt_ref = 'verification:' + [string]$verificationReceipt.receipt_id
  data_time_range = [string]$card.evidence.data_as_of
  method_ref = 'beijixing-enterprise-amazon-ad-diagnostic-v1'
  artifact_ref = $workOrderId
  integrity_hash = 'sha256:' + $packHash
  verification_status = 'passed'
  verifier_id = $VerifierId
  approver_id = $ApproverId
  uncertainties = @('real_runner_disabled', 'business_write_not_performed')
}
$workOrder=[ordered]@{
  schema_version=1; created_at=(Get-Date).ToUniversalTime().ToString('o')
  status='approved_preview'; work_order_id=$workOrderId; task_id=[string]$pack.task_id; grant_id=[string]$pack.grant_id
  action_card_index=$ActionCardIndex; campaign_id=[string]$card.campaign_id; target_id=[string]$card.target_id
  requester_id=$RequesterId; approver_id=$ApproverId; confirmation_id=$ConfirmationId; diagnostic_pack_hash=$packHash
  before_snapshot=[ordered]@{bid=$BeforeBid; budget=$BeforeBudget}
  rollback=[ordered]@{method='restore_approved_before_value'; bid=$BeforeBid; budget=$BeforeBudget}
  diagnostic_receipt_ref='receipt:' + [string]$diagnosticReceipt.receipt_id; verification_receipt_ref='verification:' + [string]$verificationReceipt.receipt_id
  post_change_verification=@('day_3','day_7'); independent_verification_required=$true
  evidence_receipt=$receipt
  execution_authorized=$false; external_calls=$false; write_performed=$false
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath=Join-Path $workOrderRoot "$workOrderId.json" }
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if (-not $outputFull.StartsWith($workOrderRoot,[StringComparison]::OrdinalIgnoreCase)) { Emit ([ordered]@{status='blocked';reason='work_order_output_outside_governed_root';execution_authorized=$false}) 1 }
if (Test-Path -LiteralPath $outputFull) { Emit ([ordered]@{status='blocked';reason='work_order_already_exists';execution_authorized=$false}) 1 }
if (-not (Test-Path -LiteralPath (Split-Path -Parent $outputFull) -PathType Container)) { New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force|Out-Null }
[IO.File]::WriteAllText($outputFull,($workOrder|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
$auditScript=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1';$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl'
$evidenceRefs=@(('receipt:'+[string]$diagnosticReceipt.receipt_id),('verification:'+[string]$verificationReceipt.receipt_id),('approval:'+$ConfirmationId))
try { & $auditScript -EventType artifact_received -Decision accept -TenantId $TenantId -OrganizationId $OrganizationId -UserId $ApproverId -AgentId ([string]$grant.agent_id) -AgentVersion ([string]$grant.agent_version) -TaskId ([string]$grant.task_id) -GrantId ([string]$grant.grant_id) -TraceId ([string]$grant.trace_id) -PolicyVersion '2.14.0' -WorkOrderRef ('work-order:'+$workOrderId) -ArtifactRefs ('work-order:'+$workOrderId) -EvidenceRefs $evidenceRefs -RunnerAttestationRef 'attestation:verified' -OutputPath $auditPath -PassThru | Out-Null } catch { Emit ([ordered]@{status='blocked';reason='work_order_audit_write_failed';work_order_persisted=$true;work_order_path=$outputFull;execution_authorized=$false}) 1 }
$workOrder.work_order_path=$outputFull;$workOrder.audit_event_path=$auditPath
Emit $workOrder 0
