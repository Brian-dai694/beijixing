<##
.SYNOPSIS
  Reads one sanitized Enterprise task timeline from the append-only audit ledger.
.DESCRIPTION
  This is an operator projection, not an authority source. It returns metadata
  and logical references only; the event stream remains the source of truth.
##>
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9._:-]{1,160}$')][string]$TaskId,
  [string]$TenantId='',
  [string]$OrganizationId='',
  [switch]$PassThru
)

$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl'
function Emit([object]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 15}else{$Value|Format-List};if($Code-ne 0){exit $Code}}
if(-not(Test-Path -LiteralPath $auditPath -PathType Leaf)){Emit ([ordered]@{status='blocked';reason='audit_ledger_missing';task_id=$TaskId;external_calls=$false}) 1}
$events=[System.Collections.Generic.List[object]]::new()
try {
  foreach($line in @(Get-Content -LiteralPath $auditPath -Encoding UTF8)) {
    if([string]::IsNullOrWhiteSpace($line)){continue}
    $event=$line|ConvertFrom-Json
    if([string]$event.task_id-ne$TaskId){continue}
    if($TenantId-and[string]$event.tenant_id-ne$TenantId){continue}
    if($OrganizationId-and[string]$event.organization_id-ne$OrganizationId){continue}
    [void]$events.Add($event)
  }
} catch { Emit ([ordered]@{status='blocked';reason='audit_ledger_invalid';task_id=$TaskId;external_calls=$false}) 1 }
if($events.Count-eq 0){Emit ([ordered]@{status='blocked';reason='task_not_found';task_id=$TaskId;external_calls=$false}) 1}
$terminal=@($events|Where-Object{$_.event_type-eq'task_terminal'}|Select-Object -Last 1);$revoked=@($events|Where-Object{$_.event_type-eq'grant_revoked'});$frozen=@($events|Where-Object{$_.event_type-eq'task_frozen'});$verification=@($events|Where-Object{$_.event_type-eq'verification_completed'}|Select-Object -Last 1)
$state=if($terminal.Count){[string]$terminal[0].decision}elseif($frozen.Count){'frozen'}elseif($revoked.Count){'revoked'}else{'active'}
$grantState=if($revoked.Count){'revoked'}elseif(@($events|Where-Object{$_.event_type-eq'grant_issued'}).Count){'issued'}else{'unknown'}
$result=[ordered]@{status='ok';task_id=$TaskId;tenant_id=[string]$events[0].tenant_id;organization_id=[string]$events[0].organization_id;current_state=$state;grant_state=$grantState;terminal_event=if($terminal.Count){$terminal[0].event_id}else{$null};verification_event=if($verification.Count){$verification[0].event_id}else{$null};event_count=$events.Count;events=@($events|ForEach-Object{[ordered]@{event_id=$_.event_id;event_type=$_.event_type;created_at=$_.created_at;tenant_id=$_.tenant_id;organization_id=$_.organization_id;task_id=$_.task_id;decision=$_.decision;agent_id=$_.agent_id;agent_version=$_.agent_version;grant_id=$_.grant_id;trace_id=$_.trace_id;policy_version=$_.policy_version;artifact_refs=@($_.artifact_refs);evidence_refs=@($_.evidence_refs)}});raw_content_returned=$false;secret_values_returned=$false;external_calls=$false}
Emit $result 0
