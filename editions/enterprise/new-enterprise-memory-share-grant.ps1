<##
.SYNOPSIS
  Issues a short-lived, non-delegable share Grant for one memory record between Agents.
##>
param(
  [Parameter(Mandatory=$true)][string]$MemoryPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$')][string]$ShareGrantId,
  [Parameter(Mandatory=$true)][string]$SourceAgentId,
  [Parameter(Mandatory=$true)][string]$TargetAgentId,
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$RoleId,
  [Parameter(Mandatory=$true)][datetime]$ExpiresAt,
  [Parameter(Mandatory=$true)][string]$ApprovedBy,
  [Parameter(Mandatory=$true)][string]$GrantId,
  [Parameter(Mandatory=$true)][string]$TraceId,
  [string]$OutputPath='',
  [switch]$PassThru
)
$ErrorActionPreference='Stop';$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path;$recordRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-memory/records')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;$shareRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-memory/share-grants')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
function Emit([hashtable]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 12}else{$Value|Format-List};if($Code-ne0){exit $Code}}
try{$memoryFull=(Resolve-Path -LiteralPath $MemoryPath -ErrorAction Stop).Path;$record=Get-Content -LiteralPath $memoryFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Emit ([ordered]@{status='blocked';reason='memory_record_not_found_or_invalid';share_grant_issued=$false}) 1};if(-not$memoryFull.StartsWith($recordRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='blocked';reason='memory_record_outside_governed_root';share_grant_issued=$false}) 1}
if($SourceAgentId-ne[string]$record.created_by_agent_id){Emit ([ordered]@{status='blocked';reason='source_agent_does_not_own_record_lineage';share_grant_issued=$false}) 1};if($SourceAgentId-eq$TargetAgentId){Emit ([ordered]@{status='blocked';reason='cross_agent_share_requires_distinct_agents';share_grant_issued=$false}) 1};if($RoleId-ne[string]$record.role_id){Emit ([ordered]@{status='blocked';reason='role_scope_mismatch';share_grant_issued=$false}) 1};if([string]::IsNullOrWhiteSpace($ApprovedBy)){Emit ([ordered]@{status='blocked';reason='explicit_share_approval_required';share_grant_issued=$false}) 1};if($ExpiresAt.ToUniversalTime()-le[DateTime]::UtcNow-or$ExpiresAt.ToUniversalTime()-gt[DateTime]::UtcNow.AddHours(24)){Emit ([ordered]@{status='blocked';reason='share_grant_expiry_out_of_bounds';share_grant_issued=$false}) 1}
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $shareRoot "$ShareGrantId.json"};$full=[IO.Path]::GetFullPath($OutputPath);if(-not$full.StartsWith($shareRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='blocked';reason='share_grant_output_outside_governed_root';share_grant_issued=$false}) 1};if(Test-Path -LiteralPath $full){Emit ([ordered]@{status='blocked';reason='share_grant_already_exists';share_grant_issued=$false}) 1}
$share=[ordered]@{schema_version=1;share_grant_id=$ShareGrantId;memory_id=[string]$record.memory_id;cube_id=[string]$record.cube_id;memory_layer=[string]$record.memory_layer;tenant_id=[string]$record.tenant_id;organization_id=[string]$record.organization_id;project_id=[string]$record.project_id;role_id=[string]$record.role_id;classification=[string]$record.classification;source_agent_id=$SourceAgentId;target_agent_id=$TargetAgentId;task_id=$TaskId;approved_by=$ApprovedBy;issued_at=[DateTime]::UtcNow.ToString('o');expires_at=$ExpiresAt.ToUniversalTime().ToString('o');status='issued';can_delegate=$false;execution_authority=$false;permission_authority=$false}
New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force|Out-Null;[IO.File]::WriteAllText($full,($share|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false));$audit=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1';try{& $audit -EventType memory_share_issued -Decision allow -TenantId ([string]$record.tenant_id) -OrganizationId ([string]$record.organization_id) -UserId $ApprovedBy -AgentId $SourceAgentId -AgentVersion 'memory-share-v1' -TaskId $TaskId -GrantId $GrantId -TraceId $TraceId -PolicyVersion '2.14.0' -DataRefs @((('memory://'+[string]$record.memory_id)),(('memory-cube://'+[string]$record.cube_id))) -EvidenceRefs ('memory-share://'+$ShareGrantId) -PassThru|Out-Null}catch{Emit ([ordered]@{status='blocked';reason='share_grant_audit_failed';share_grant_issued=$true;share_grant_path=$full}) 1};Emit ([ordered]@{status='issued';share_grant_id=$ShareGrantId;share_grant_path=$full;share_grant_issued=$true;can_delegate=$false;execution_authority=$false;external_calls=$false})
