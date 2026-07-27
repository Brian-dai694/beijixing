<##
.SYNOPSIS
  Closes one Enterprise task by revoking its Grant and appending one terminal event.
.DESCRIPTION
  Completion requires an independently verified evidence receipt. Cancellation and
  freeze preserve the trace but cannot be reported as successful completion.
##>
param(
  [Parameter(Mandatory=$true)][string]$GrantPath,
  [Parameter(Mandatory=$true)][string]$ActorId,
  [Parameter(Mandatory=$true)][ValidateSet('completed','cancelled','frozen')][string]$TerminalStatus,
  [ValidateSet('passed','failed','pending','not_applicable')][string]$VerificationStatus='pending',
  [string]$EvidenceReceiptRef='',
  [string]$Reason='task_terminal',
  [switch]$PassThru
)

$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl'
$revoker=Join-Path $PSScriptRoot 'revoke-enterprise-grant.ps1'
$powerShellResolver=Join-Path $PSScriptRoot 'resolve-enterprise-powershell.ps1';. $powerShellResolver;$powerShellCommand=Get-EnterprisePowerShellCommand
function Emit([object]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 15}else{$Value|Format-List};if($Code-ne 0){exit $Code}}

try{$grantFull=(Resolve-Path -LiteralPath $GrantPath -ErrorAction Stop).Path}catch{Emit ([ordered]@{status='blocked';reason='grant_not_found';execution_authorized=$false}) 1}
try{$grant=Get-Content -LiteralPath $grantFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Emit ([ordered]@{status='blocked';reason='grant_invalid';execution_authorized=$false}) 1}
if([string]::IsNullOrWhiteSpace([string]$grant.grant_id)-or[string]::IsNullOrWhiteSpace([string]$grant.task_id)){Emit ([ordered]@{status='blocked';reason='grant_identity_incomplete';execution_authorized=$false}) 1}
if([string]::IsNullOrWhiteSpace($ActorId)){Emit ([ordered]@{status='blocked';reason='actor_required';execution_authorized=$false}) 1}
if($TerminalStatus-eq'completed' -and ($VerificationStatus-ne'passed' -or [string]::IsNullOrWhiteSpace($EvidenceReceiptRef))){Emit ([ordered]@{status='blocked';reason='verified_receipt_required_for_completion';execution_authorized=$false}) 1}
if([string]::IsNullOrWhiteSpace($Reason)-or$Reason-match'(?i)(api[_-]?key|token|password|cookie|secret_value|raw_prompt|hidden_reasoning)'){Emit ([ordered]@{status='blocked';reason='unsafe_terminal_reason';execution_authorized=$false}) 1}

$existingTerminal=@()
if(Test-Path -LiteralPath $auditPath -PathType Leaf){
  try{$existingTerminal=@(Get-Content -LiteralPath $auditPath -Encoding UTF8|ForEach-Object{if(-not[string]::IsNullOrWhiteSpace($_)){$_|ConvertFrom-Json}}|Where-Object{$_.event_type-eq'task_terminal'-and$_.task_id-eq[string]$grant.task_id})}catch{Emit ([ordered]@{status='blocked';reason='audit_ledger_invalid';execution_authorized=$false}) 1}
}
if(@($existingTerminal).Count-gt 0){Emit ([ordered]@{status='blocked';reason='task_already_terminal';task_id=[string]$grant.task_id;execution_authorized=$false}) 1}

$revokeRaw=@(& $powerShellCommand -NoProfile -ExecutionPolicy Bypass -File $revoker -GrantPath $grantFull -ActorId $ActorId -Reason $Reason -PassThru 2>&1)
$revokeCode=$LASTEXITCODE;$revokeText=($revokeRaw|ForEach-Object{$_.ToString()})-join "`n";$revoke=$null
try{$revoke=$revokeText|ConvertFrom-Json}catch{}
if($revokeCode-ne 0 -or $null-eq$revoke -or $revoke.status-ne'revoked'){Emit ([ordered]@{status='blocked';reason='grant_revocation_failed';revocation=$revoke;execution_authorized=$false;external_calls=$false}) 1}

$audit=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
$auditArgs=@('-EventType','task_terminal','-Decision',$(if($TerminalStatus-eq'completed'){'accept'}else{'freeze'}),'-TenantId',[string]$grant.tenant_id,'-OrganizationId',[string]$grant.organization_id,'-UserId',$ActorId,'-AgentId',[string]$grant.agent_id,'-AgentVersion',[string]$grant.agent_version,'-TaskId',[string]$grant.task_id,'-GrantId',[string]$grant.grant_id,'-TraceId',[string]$grant.trace_id,'-PolicyVersion','2.14.0','-EvidenceRefs',@($EvidenceReceiptRef,'revocation:'+[string]$revoke.revocation.revocation_id),'-OutputPath',$auditPath)
& $powerShellCommand -NoProfile -ExecutionPolicy Bypass -File $audit @auditArgs|Out-Null
if($LASTEXITCODE-ne 0){Emit ([ordered]@{status='blocked';reason='terminal_audit_write_failed';grant_revoked=$true;execution_authorized=$false;external_calls=$false}) 1}
Emit ([ordered]@{status=$TerminalStatus;task_id=[string]$grant.task_id;grant_id=[string]$grant.grant_id;grant_revoked=$true;verification_status=$VerificationStatus;evidence_receipt_ref=$EvidenceReceiptRef;execution_authorized=$false;external_calls=$false;process_started=$false}) 0
