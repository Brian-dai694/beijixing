<##
.SYNOPSIS
  Creates one immutable candidate enterprise-memory record containing references only.
##>
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$')][string]$MemoryId,
  [Parameter(Mandatory=$true)][ValidateSet('task','agent','organization','knowledge','evidence','audit')][string]$MemoryType,
  [Parameter(Mandatory=$true)][ValidateSet('trajectory','strategy','world_model','skill')][string]$MemoryLayer,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$')][string]$CubeId,
  [Parameter(Mandatory=$true)][string]$ContentRef,
  [Parameter(Mandatory=$true)][string]$Scope,
  [Parameter(Mandatory=$true)][string[]]$SourceRefs,
  [Parameter(Mandatory=$true)][ValidateRange(0,1)][double]$Confidence,
  [Parameter(Mandatory=$true)][datetime]$ExpiresAt,
  [Parameter(Mandatory=$true)][ValidateSet('task_bound','agent_bound','organization_scoped','authorized_only','audit_only')][string]$Visibility,
  [Parameter(Mandatory=$true)][string]$TenantId,
  [Parameter(Mandatory=$true)][string]$OrganizationId,
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [Parameter(Mandatory=$true)][string]$RoleId,
  [Parameter(Mandatory=$true)][ValidateSet('public','internal_sanitized','confidential_reference_only','restricted_reference_only')][string]$Classification,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')][string]$RecordVersion,
  [Parameter(Mandatory=$true)][string]$OwnerId,
  [Parameter(Mandatory=$true)][string]$AuditChainRef,
  [Parameter(Mandatory=$true)][string]$ActorId,
  [Parameter(Mandatory=$true)][string]$AgentId,
  [Parameter(Mandatory=$true)][string]$AgentVersion,
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$GrantId,
  [Parameter(Mandatory=$true)][string]$TraceId,
  [switch]$ApprovalRequired,
  [string]$OutputPath='',
  [switch]$PassThru
)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$recordRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-memory/records')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$forbidden='(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|password|cookie|authorization:|raw_prompt|hidden_reasoning|secret_value|raw_private_data|raw_customer_data)'
$referencePattern='^(?:[a-z][a-z0-9+.-]*://|sha256:)[^\s]+$'
function Emit([hashtable]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 12}else{$Value|Format-List};if($Code-ne0){exit $Code}}
if($ContentRef-notmatch$referencePattern-or@($SourceRefs|Where-Object{$_-notmatch$referencePattern}).Count){Emit ([ordered]@{status='blocked';reason='reference_only_fields_required';memory_written=$false;external_calls=$false}) 1}
foreach($value in @($ContentRef,$Scope,$TenantId,$OrganizationId,$ProjectId,$RoleId,$OwnerId,$AuditChainRef,$ActorId,$AgentId,$AgentVersion,$TaskId,$GrantId,$TraceId)+@($SourceRefs)){if([string]$value-match$forbidden){Emit ([ordered]@{status='blocked';reason='prohibited_sensitive_memory_content';memory_written=$false;external_calls=$false}) 1}}
if($AuditChainRef-notmatch$referencePattern){Emit ([ordered]@{status='blocked';reason='audit_chain_reference_required';memory_written=$false;external_calls=$false}) 1}
if($ExpiresAt.ToUniversalTime()-le[DateTime]::UtcNow){Emit ([ordered]@{status='blocked';reason='memory_expiry_must_be_future';memory_written=$false;external_calls=$false}) 1}
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $recordRoot "$MemoryId.json"}
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if(-not$outputFull.StartsWith($recordRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='blocked';reason='memory_output_outside_governed_root';memory_written=$false;external_calls=$false}) 1}
if(Test-Path -LiteralPath $outputFull){Emit ([ordered]@{status='blocked';reason='memory_record_already_exists';memory_written=$false;external_calls=$false}) 1}
$now=[DateTime]::UtcNow.ToString('o')
$record=[ordered]@{schema_version=2;memory_id=$MemoryId;memory_type=$MemoryType;memory_layer=$MemoryLayer;cube_id=$CubeId;content_ref=$ContentRef;scope=$Scope;source_refs=@($SourceRefs);created_at=$now;updated_at=$now;confidence=$Confidence;expires_at=$ExpiresAt.ToUniversalTime().ToString('o');visibility=$Visibility;status='candidate';tenant_id=$TenantId;organization_id=$OrganizationId;project_id=$ProjectId;role_id=$RoleId;classification=$Classification;record_version=$RecordVersion;owner_id=$OwnerId;audit_chain_ref=$AuditChainRef;created_by_agent_id=$AgentId;approval_required=[bool]$ApprovalRequired;permission_authority=$false;provenance=@([ordered]@{event_id='creation';source_ref=[string]$SourceRefs[0];observed_at=$now;actor_id=$ActorId;verification_status='candidate'})}
New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force|Out-Null
[IO.File]::WriteAllText($outputFull,($record|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
$audit=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
try{& $audit -EventType memory_candidate_created -Decision accept -TenantId $TenantId -OrganizationId $OrganizationId -UserId $ActorId -AgentId $AgentId -AgentVersion $AgentVersion -TaskId $TaskId -GrantId $GrantId -TraceId $TraceId -PolicyVersion '2.14.0' -DataRefs @((('memory://'+$MemoryId)),(('memory-cube://'+$CubeId))) -ArtifactRefs ('memory-record://'+$MemoryId) -EvidenceRefs (@($SourceRefs)+@($AuditChainRef)) -PassThru|Out-Null}catch{Emit ([ordered]@{status='blocked';reason='memory_audit_write_failed';memory_written=$true;memory_path=$outputFull;external_calls=$false}) 1}
Emit ([ordered]@{status='candidate';memory_id=$MemoryId;memory_path=$outputFull;memory_written=$true;raw_content_stored=$false;external_calls=$false})
