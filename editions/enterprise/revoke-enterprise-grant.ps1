<##
.SYNOPSIS
  Revokes an Enterprise Grant through an append-only revocation ledger.
.DESCRIPTION
  The Grant document is never edited. The Broker checks the ledger before each
  governed action, so task end, cancellation, expiry response, or incident
  response can invalidate the Grant without rewriting history.
##>
param(
  [Parameter(Mandatory=$true)][string]$GrantPath,
  [Parameter(Mandatory=$true)][string]$ActorId,
  [Parameter(Mandatory=$true)][string]$Reason,
  [string]$OutputPath='',
  [switch]$PassThru
)

$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$grantRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\delegation-grants')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$revocationRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$powerShellResolver=Join-Path $PSScriptRoot 'resolve-enterprise-powershell.ps1';. $powerShellResolver;$powerShellCommand=Get-EnterprisePowerShellCommand
function Emit([object]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 12}else{$Value|Format-List};if($Code-ne 0){exit $Code}}
try{$grantFull=(Resolve-Path -LiteralPath $GrantPath -ErrorAction Stop).Path}catch{Emit ([ordered]@{status='blocked';reason='grant_not_found';revoked=$false}) 1}
if(-not$grantFull.StartsWith($grantRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='blocked';reason='grant_outside_governed_root';revoked=$false}) 1}
try{$grant=Get-Content -LiteralPath $grantFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Emit ([ordered]@{status='blocked';reason='grant_invalid';revoked=$false}) 1}
if([string]::IsNullOrWhiteSpace($grant.grant_id)-or[string]::IsNullOrWhiteSpace($grant.task_id)){Emit ([ordered]@{status='blocked';reason='grant_identity_incomplete';revoked=$false}) 1}
if([string]::IsNullOrWhiteSpace($Reason)-or$Reason-match'(?i)(api[_-]?key|token|password|cookie|secret_value|raw_prompt|hidden_reasoning)'){Emit ([ordered]@{status='blocked';reason='unsafe_revocation_reason';revoked=$false}) 1}
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $revocationRoot 'grant-revocations.jsonl'}
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if(-not$outputFull.StartsWith($revocationRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='blocked';reason='revocation_output_outside_governed_root';revoked=$false}) 1}
if(-not(Test-Path -LiteralPath (Split-Path -Parent $outputFull) -PathType Container)){New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force|Out-Null}
$record=[ordered]@{schema_version=1;revocation_id=[Guid]::NewGuid().ToString('n');grant_id=[string]$grant.grant_id;task_id=[string]$grant.task_id;agent_id=[string]$grant.agent_id;actor_id=$ActorId;reason=$Reason;revoked_at=(Get-Date).ToUniversalTime().ToString('o')}
[IO.File]::AppendAllText($outputFull,(($record|ConvertTo-Json -Depth 8 -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
$audit=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1';$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl'
$auditArgs=@('-EventType','grant_revoked','-Decision','revoke','-TenantId',[string]$grant.tenant_id,'-OrganizationId',[string]$grant.organization_id,'-UserId',$ActorId,'-AgentId',[string]$grant.agent_id,'-AgentVersion',[string]$grant.agent_version,'-TaskId',[string]$grant.task_id,'-GrantId',[string]$grant.grant_id,'-TraceId',[string]$grant.trace_id,'-PolicyVersion','2.14.0','-EvidenceRefs',('revocation:'+ $record.revocation_id),'-OutputPath',$auditPath)
& $powerShellCommand -NoProfile -ExecutionPolicy Bypass -File $audit @auditArgs|Out-Null
if($LASTEXITCODE-ne 0){Emit ([ordered]@{status='blocked';reason='revocation_audit_write_failed';revoked=$false}) 1}
Emit ([ordered]@{status='revoked';revocation=$record;revocation_path=$outputFull;audit_event_path=$auditPath;revoked=$true;execution_authorized=$false;external_calls=$false}) 0
