<##
.SYNOPSIS
  Appends one validated Enterprise audit event to the local trace stream.
.DESCRIPTION
  This writer accepts metadata and references only. It rejects secrets, raw
  prompts, hidden reasoning, and unrestricted private data, and never rewrites
  or deletes an existing event.
##>
param(
  [Parameter(Mandatory=$true)][ValidateSet('task_created','grant_issued','grant_checked','grant_revoked','tool_allowed','tool_denied','tool_registered','tool_static_checked','tool_sandboxed','tool_approved','tool_canary_started','tool_activated','tool_suspended','tool_rolled_back','tool_revoked','tool_call_screened','tool_feedback_candidate_created','obsidian_note_exported','obsidian_feedback_candidate_created','artifact_received','verification_completed','task_frozen','task_terminal','memory_candidate_created','memory_verified','memory_activated','memory_staled','memory_superseded','memory_revoked','memory_deleted','memory_read_requested','memory_share_issued','memory_share_revoked','skill_candidate_created','skill_trial_started','skill_approved','skill_activated','skill_suspended','skill_rolled_back','skill_revoked')][string]$EventType,
  [Parameter(Mandatory=$true)][ValidateSet('allow','deny','shrink','pause','isolate','revoke','freeze','accept','reject')][string]$Decision,
  [Parameter(Mandatory=$true)][string]$TenantId,
  [Parameter(Mandatory=$true)][string]$OrganizationId,
  [Parameter(Mandatory=$true)][string]$UserId,
  [Parameter(Mandatory=$true)][string]$AgentId,
  [Parameter(Mandatory=$true)][string]$AgentVersion,
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$GrantId,
  [Parameter(Mandatory=$true)][string]$TraceId,
  [Parameter(Mandatory=$true)][string]$PolicyVersion,
  [string[]]$DataRefs=@(),
  [string]$WorkOrderRef='',
  [string[]]$ArtifactRefs=@(),
  [string[]]$EvidenceRefs=@(),
  [string]$RunnerAttestationRef='',
  [string]$PolicyRef='',
  [string]$DecisionReason='',
  [string]$SideEffectSummary='',
  [string]$VerificationRef='',
  [string]$ResponsibleParty='',
  [string]$OutputPath='',
  [switch]$PassThru
)

$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$auditRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$forbidden='(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|password|cookie|authorization:|raw_prompt|hidden_reasoning|secret_value)'
foreach($value in @($TenantId,$OrganizationId,$UserId,$AgentId,$AgentVersion,$TaskId,$GrantId,$TraceId,$PolicyVersion,$WorkOrderRef,$RunnerAttestationRef,$PolicyRef,$DecisionReason,$SideEffectSummary,$VerificationRef,$ResponsibleParty)+@($DataRefs)+@($ArtifactRefs)+@($EvidenceRefs)){if([string]$value-match$forbidden){throw 'Audit metadata contains prohibited secret or raw-content material.'}}
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $auditRoot 'enterprise-audit-events.jsonl'}
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if(-not $outputFull.StartsWith($auditRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Audit output must remain under .qianlima/run-traces.'}
if(-not(Test-Path -LiteralPath (Split-Path -Parent $outputFull) -PathType Container)){New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force|Out-Null}
$event=[ordered]@{
  schema_version=1;event_id=[Guid]::NewGuid().ToString('n');event_type=$EventType;created_at=(Get-Date).ToUniversalTime().ToString('o')
  tenant_id=$TenantId;organization_id=$OrganizationId;user_id=$UserId;agent_id=$AgentId;agent_version=$AgentVersion
  task_id=$TaskId;grant_id=$GrantId;trace_id=$TraceId;policy_version=$PolicyVersion;decision=$Decision
  work_order_ref=if($WorkOrderRef){$WorkOrderRef}else{$null};artifact_refs=@($ArtifactRefs);evidence_refs=@($EvidenceRefs)
  runner_attestation_ref=if($RunnerAttestationRef){$RunnerAttestationRef}else{$null};data_refs=@($DataRefs)
  policy_ref=if($PolicyRef){$PolicyRef}else{$null};decision_reason=if($DecisionReason){$DecisionReason}else{$null}
  side_effect_summary=if($SideEffectSummary){$SideEffectSummary}else{$null};verification_ref=if($VerificationRef){$VerificationRef}else{$null}
  responsible_party=if($ResponsibleParty){$ResponsibleParty}else{$null}
}
$line=($event|ConvertTo-Json -Depth 12 -Compress)+[Environment]::NewLine
[IO.File]::AppendAllText($outputFull,$line,[Text.UTF8Encoding]::new($false))
if($PassThru){$event|ConvertTo-Json -Depth 12}else{Write-Host "Enterprise audit event written: $($event.event_id)"}
