<##
.SYNOPSIS
  Independently verifies an Enterprise read-only advertising receipt.
.DESCRIPTION
  Re-hashes the original local snapshot and checks task, Grant, Agent, and
  safety bindings. It never re-runs the diagnostic, calls a Provider, or
  changes the original receipt. A successful result writes a separate,
  append-only-style verification receipt under the governed trace root.
##>
param(
  [Parameter(Mandatory=$true)][string]$ReceiptPath,
  [Parameter(Mandatory=$true)][string]$SourcePath,
  [Parameter(Mandatory=$true)][string]$VerifierId,
  [Parameter(Mandatory=$true)][string]$ExpectedTaskId,
  [Parameter(Mandatory=$true)][string]$ExpectedGrantId,
  [string]$VerificationReceiptPath='',
  [switch]$PassThru
)

$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$receiptRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\enterprise-receipts')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar

function Emit([object]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 15}else{$Value|Format-List};if($Code-ne 0){exit $Code}}
function Under-Root([string]$Path){return([IO.Path]::GetFullPath($Path)).StartsWith($receiptRoot,[StringComparison]::OrdinalIgnoreCase)}

$issues=[System.Collections.Generic.List[string]]::new()
try{$receiptFull=(Resolve-Path -LiteralPath $ReceiptPath -ErrorAction Stop).Path}catch{Emit ([ordered]@{status='blocked';reason='receipt_not_found';external_calls=$false;write_performed=$false}) 1}
if(-not(Under-Root $receiptFull)){Emit ([ordered]@{status='blocked';reason='receipt_outside_governed_root';external_calls=$false;write_performed=$false}) 1}
try{$receipt=Get-Content -LiteralPath $receiptFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Emit ([ordered]@{status='blocked';reason='receipt_invalid';external_calls=$false;write_performed=$false}) 1}
if(-not(Test-Path -LiteralPath $SourcePath -PathType Leaf)){Emit ([ordered]@{status='blocked';reason='source_not_found';external_calls=$false;write_performed=$false}) 1}
if([string]$receipt.receipt_type-ne'enterprise_readonly_diagnostic'){[void]$issues.Add('receipt_type_mismatch')}
if([string]$receipt.task_id-ne$ExpectedTaskId){[void]$issues.Add('task_binding_mismatch')}
if([string]$receipt.grant_id-ne$ExpectedGrantId){[void]$issues.Add('grant_binding_mismatch')}
if([string]$receipt.agent_id-eq$VerifierId){[void]$issues.Add('independent_verifier_required')}
if([string]$receipt.verification_status-ne'pending_review'){[void]$issues.Add('receipt_not_pending_review')}
if($receipt.external_calls-ne$false){[void]$issues.Add('external_call_boundary_failed')}
if($receipt.execution_authorized-ne$false){[void]$issues.Add('execution_authority_boundary_failed')}
if($receipt.write_performed-ne$false){[void]$issues.Add('write_boundary_failed')}
if($receipt.raw_rows_recorded-ne$false){[void]$issues.Add('raw_rows_boundary_failed')}
$sourceHash=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
if($sourceHash-ne[string]$receipt.source_hash){[void]$issues.Add('source_hash_mismatch')}
if($issues.Count){Emit ([ordered]@{status='blocked';reason='receipt_verification_failed';issues=@($issues);receipt_id=[string]$receipt.receipt_id;external_calls=$false;write_performed=$false}) 1}

$verificationId='verification-ad-diagnostic-v1-'+[Guid]::NewGuid().ToString('n')
$verification=[ordered]@{
  schema_version=1; receipt_id=$verificationId; receipt_type='independent_verification_receipt'
  parent_receipt_id=[string]$receipt.receipt_id; task_id=$ExpectedTaskId; grant_id=$ExpectedGrantId
  verifier_id=$VerifierId; source_hash=$sourceHash; verification_status='passed'; independent_verification=$true
  external_calls=$false; execution_authorized=$false; write_performed=$false; raw_rows_recorded=$false
  verified_at=(Get-Date).ToUniversalTime().ToString('o')
}
if([string]::IsNullOrWhiteSpace($VerificationReceiptPath)){$VerificationReceiptPath=Join-Path $receiptRoot "$verificationId.json"}
$verificationFull=[IO.Path]::GetFullPath($VerificationReceiptPath)
if(-not(Under-Root $verificationFull)){Emit ([ordered]@{status='blocked';reason='verification_receipt_outside_governed_root';external_calls=$false;write_performed=$false}) 1}
if(-not(Test-Path -LiteralPath (Split-Path -Parent $verificationFull) -PathType Container)){New-Item -ItemType Directory -Path (Split-Path -Parent $verificationFull) -Force|Out-Null}
[IO.File]::WriteAllText($verificationFull,($verification|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
$auditScript=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
$powerShellResolver=Join-Path $PSScriptRoot 'resolve-enterprise-powershell.ps1';. $powerShellResolver;$powerShellCommand=Get-EnterprisePowerShellCommand
$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl'
$auditArgs=@('-EventType','verification_completed','-Decision','allow','-TenantId',[string]$receipt.tenant_id,'-OrganizationId',[string]$receipt.organization_id,'-UserId',[string]$receipt.employee_id,'-AgentId',[string]$receipt.agent_id,'-AgentVersion',[string]$receipt.agent_version,'-TaskId',$ExpectedTaskId,'-GrantId',$ExpectedGrantId,'-TraceId',[string]$receipt.trace_id,'-PolicyVersion','2.14.0','-DataRefs',('snapshot:sha256:'+$sourceHash),'-ArtifactRefs',('verification:'+ $verificationId),'-EvidenceRefs',('receipt:'+[string]$receipt.receipt_id),'-RunnerAttestationRef','attestation:verified','-OutputPath',$auditPath)
& $powerShellCommand -NoProfile -ExecutionPolicy Bypass -File $auditScript @auditArgs | Out-Null
if($LASTEXITCODE-ne 0){Emit ([ordered]@{status='blocked';reason='audit_event_write_failed';verification=$verification;external_calls=$false;write_performed=$false}) 1}
Emit ([ordered]@{status='verified';verification=$verification;verification_receipt_path=$verificationFull;audit_event_path=$auditPath;external_calls=$false;execution_authorized=$false;write_performed=$false;process_started=$false}) 0
