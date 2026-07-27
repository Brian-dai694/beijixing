<##
.SYNOPSIS
  Appends one validated enterprise-memory lifecycle transition without changing the record.
##>
param(
  [Parameter(Mandatory=$true)][string]$MemoryPath,
  [Parameter(Mandatory=$true)][ValidateSet('verified','active','stale','superseded','revoked','deleted')][string]$ToStatus,
  [Parameter(Mandatory=$true)][string]$ActorId,
  [Parameter(Mandatory=$true)][string]$AgentId,
  [Parameter(Mandatory=$true)][string]$AgentVersion,
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$GrantId,
  [Parameter(Mandatory=$true)][string]$TraceId,
  [string]$EvidenceRef='',
  [string]$ApprovedBy='',
  [string]$SupersededBy='',
  [switch]$PassThru
)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$recordRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-memory/records')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$ledgerPath=Join-Path $projectRoot '.qianlima/run-traces/enterprise-memory/lifecycle.jsonl'
function Emit([hashtable]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 12}else{$Value|Format-List};if($Code-ne0){exit $Code}}
try{$full=(Resolve-Path -LiteralPath $MemoryPath -ErrorAction Stop).Path}catch{Emit ([ordered]@{status='blocked';reason='memory_record_not_found';transition_written=$false}) 1}
if(-not$full.StartsWith($recordRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='blocked';reason='memory_record_outside_governed_root';transition_written=$false}) 1}
try{$record=Get-Content -LiteralPath $full -Raw -Encoding UTF8|ConvertFrom-Json}catch{Emit ([ordered]@{status='blocked';reason='memory_record_invalid';transition_written=$false}) 1}
$current=[string]$record.status
if(Test-Path -LiteralPath $ledgerPath){foreach($line in @(Get-Content -LiteralPath $ledgerPath -Encoding UTF8)){if([string]::IsNullOrWhiteSpace($line)){continue};try{$event=$line|ConvertFrom-Json;if([string]$event.memory_id-eq[string]$record.memory_id){$current=[string]$event.to_status}}catch{Emit ([ordered]@{status='blocked';reason='memory_lifecycle_ledger_invalid';transition_written=$false}) 1}}}
$allowed=@{candidate=@('verified','revoked','deleted');verified=@('active','revoked','deleted');active=@('stale','superseded','revoked','deleted');stale=@('superseded','revoked','deleted');superseded=@('revoked','deleted');revoked=@('deleted');deleted=@()}
if(@($allowed[$current])-notcontains$ToStatus){Emit ([ordered]@{status='blocked';reason='invalid_memory_state_transition';from_status=$current;to_status=$ToStatus;transition_written=$false}) 1}
if($ToStatus-eq'verified'-and[string]::IsNullOrWhiteSpace($EvidenceRef)){Emit ([ordered]@{status='blocked';reason='verification_evidence_required';transition_written=$false}) 1}
if($ToStatus-eq'active'-and[bool]$record.approval_required-and[string]::IsNullOrWhiteSpace($ApprovedBy)){Emit ([ordered]@{status='blocked';reason='human_approval_required_for_activation';transition_written=$false}) 1}
if($ToStatus-eq'superseded'-and[string]::IsNullOrWhiteSpace($SupersededBy)){Emit ([ordered]@{status='blocked';reason='superseding_memory_reference_required';transition_written=$false}) 1}
$event=[ordered]@{schema_version=1;event_id=[Guid]::NewGuid().ToString('n');memory_id=[string]$record.memory_id;from_status=$current;to_status=$ToStatus;actor_id=$ActorId;approved_by=if($ApprovedBy){$ApprovedBy}else{$null};evidence_ref=if($EvidenceRef){$EvidenceRef}else{$null};superseded_by=if($SupersededBy){$SupersededBy}else{$null};created_at=[DateTime]::UtcNow.ToString('o')}
New-Item -ItemType Directory -Path (Split-Path -Parent $ledgerPath) -Force|Out-Null
[IO.File]::AppendAllText($ledgerPath,(($event|ConvertTo-Json -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
$eventType=@{verified='memory_verified';active='memory_activated';stale='memory_staled';superseded='memory_superseded';revoked='memory_revoked';deleted='memory_deleted'}[$ToStatus]
$decision=if($ToStatus-in@('revoked','deleted')){'revoke'}elseif($ToStatus-eq'stale'){'pause'}else{'accept'}
$audit=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1';$evidence=@($EvidenceRef,$SupersededBy|Where-Object{-not[string]::IsNullOrWhiteSpace($_)})
try{& $audit -EventType $eventType -Decision $decision -TenantId ([string]$record.tenant_id) -OrganizationId ([string]$record.organization_id) -UserId $ActorId -AgentId $AgentId -AgentVersion $AgentVersion -TaskId $TaskId -GrantId $GrantId -TraceId $TraceId -PolicyVersion '2.14.0' -DataRefs @((('memory://'+[string]$record.memory_id)),(('memory-cube://'+[string]$record.cube_id))) -EvidenceRefs $evidence -PassThru|Out-Null}catch{Emit ([ordered]@{status='blocked';reason='memory_transition_audit_write_failed';transition_written=$true;effective_status=$ToStatus}) 1}
Emit ([ordered]@{status='transitioned';memory_id=[string]$record.memory_id;from_status=$current;effective_status=$ToStatus;transition_written=$true;record_mutated=$false;external_calls=$false})
