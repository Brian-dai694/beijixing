<##
.SYNOPSIS
  Returns one minimum enterprise-memory reference pack after task-Grant checks.
##>
param(
  [Parameter(Mandatory=$true)][string]$MemoryPath,
  [Parameter(Mandatory=$true)][string]$GrantPath,
  [Parameter(Mandatory=$true)][string]$TenantId,
  [Parameter(Mandatory=$true)][string]$OrganizationId,
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [Parameter(Mandatory=$true)][string]$RoleId,
  [Parameter(Mandatory=$true)][string]$AgentId,
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$Purpose,
  [string]$ShareGrantPath='',
  [switch]$ExternalAgent,
  [switch]$PassThru
)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$recordRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-memory/records')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$grantRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/delegation-grants')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$ledgerPath=Join-Path $projectRoot '.qianlima/run-traces/enterprise-memory/lifecycle.jsonl';$revocationPath=Join-Path $projectRoot '.qianlima/run-traces/grant-revocations.jsonl'
$shareRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-memory/share-grants')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;$shareRevocationPath=Join-Path $projectRoot '.qianlima/run-traces/enterprise-memory/share-revocations.jsonl'
function Emit([hashtable]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 12}else{$Value|Format-List};if($Code-ne0){exit $Code}}
try{$memoryFull=(Resolve-Path -LiteralPath $MemoryPath -ErrorAction Stop).Path;$grantFull=(Resolve-Path -LiteralPath $GrantPath -ErrorAction Stop).Path}catch{Emit ([ordered]@{status='denied';reason='memory_or_grant_not_found';contents_returned=$false;external_calls=$false}) 1}
if(-not$memoryFull.StartsWith($recordRoot,[StringComparison]::OrdinalIgnoreCase)-or-not$grantFull.StartsWith($grantRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='denied';reason='memory_or_grant_outside_governed_root';contents_returned=$false;external_calls=$false}) 1}
try{$record=Get-Content -LiteralPath $memoryFull -Raw -Encoding UTF8|ConvertFrom-Json;$grant=Get-Content -LiteralPath $grantFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Emit ([ordered]@{status='denied';reason='memory_or_grant_invalid';contents_returned=$false;external_calls=$false}) 1}
if($ExternalAgent){Emit ([ordered]@{status='denied';reason='external_agent_requires_separate_sanitized_projection';memory_id=[string]$record.memory_id;contents_returned=$false;external_calls=$false}) 1}
$violations=[System.Collections.Generic.List[string]]::new();function Deny([string]$Reason){[void]$violations.Add($Reason)}
if([string]$grant.status-ne'issued'){Deny 'grant_not_issued'}
try{if([DateTime]::Parse([string]$grant.expires_at).ToUniversalTime()-le[DateTime]::UtcNow){Deny 'grant_expired'}}catch{Deny 'grant_expiry_invalid'}
if([string]$grant.tenant_id-ne$TenantId-or[string]$record.tenant_id-ne$TenantId){Deny 'tenant_mismatch'}
if([string]$grant.organization_id-ne$OrganizationId-or[string]$record.organization_id-ne$OrganizationId){Deny 'organization_mismatch'}
if([string]$grant.project_id-ne$ProjectId-or[string]$record.project_id-ne$ProjectId){Deny 'project_mismatch'}
if([string]$grant.role_id-ne$RoleId-or[string]$record.role_id-ne$RoleId){Deny 'role_mismatch'}
if([string]$grant.agent_id-ne$AgentId){Deny 'agent_grant_mismatch'}
if([string]$grant.task_id-ne$TaskId){Deny 'task_grant_mismatch'}
if(@($grant.allowed_tools)-notcontains'read_memory'){Deny 'read_memory_tool_not_granted'}
$memoryRef='memory://'+[string]$record.memory_id;if(@($grant.data_refs)-notcontains$memoryRef){Deny 'memory_reference_outside_grant'}
$cubeRef='memory-cube://'+[string]$record.cube_id;if(@($grant.data_refs)-notcontains$cubeRef){Deny 'memory_cube_outside_grant'}
if(@($grant.allowed_data_classifications)-notcontains[string]$record.classification){Deny 'memory_classification_outside_grant'}
if([string]::IsNullOrWhiteSpace($Purpose)){Deny 'purpose_required'}
if(Test-Path -LiteralPath $revocationPath){foreach($line in @(Get-Content -LiteralPath $revocationPath -Encoding UTF8)){if([string]::IsNullOrWhiteSpace($line)){continue};try{$r=$line|ConvertFrom-Json;if([string]$r.grant_id-eq[string]$grant.grant_id){Deny 'grant_revoked';break}}catch{Deny 'grant_revocation_ledger_invalid';break}}}
$effective=[string]$record.status
if(Test-Path -LiteralPath $ledgerPath){foreach($line in @(Get-Content -LiteralPath $ledgerPath -Encoding UTF8)){if([string]::IsNullOrWhiteSpace($line)){continue};try{$e=$line|ConvertFrom-Json;if([string]$e.memory_id-eq[string]$record.memory_id){$effective=[string]$e.to_status}}catch{Deny 'memory_lifecycle_ledger_invalid';break}}}
if($effective-ne'active'){Deny ('memory_not_active_'+$effective)}
try{if([DateTime]::Parse([string]$record.expires_at).ToUniversalTime()-le[DateTime]::UtcNow){Deny 'memory_expired'}}catch{Deny 'memory_expiry_invalid'}
if($AgentId-ne[string]$record.created_by_agent_id){
  if([string]::IsNullOrWhiteSpace($ShareGrantPath)){Deny 'cross_agent_memory_share_grant_required'}else{
    try{$shareFull=(Resolve-Path -LiteralPath $ShareGrantPath -ErrorAction Stop).Path;$share=Get-Content -LiteralPath $shareFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Deny 'memory_share_grant_not_found_or_invalid';$share=$null}
    if($null-ne$share){
      if(-not$shareFull.StartsWith($shareRoot,[StringComparison]::OrdinalIgnoreCase)){Deny 'memory_share_grant_outside_governed_root'}
      if([string]$share.status-ne'issued'){Deny 'memory_share_grant_not_issued'}
      try{if([DateTime]::Parse([string]$share.expires_at).ToUniversalTime()-le[DateTime]::UtcNow){Deny 'memory_share_grant_expired'}}catch{Deny 'memory_share_grant_expiry_invalid'}
      if([string]$share.memory_id-ne[string]$record.memory_id-or[string]$share.cube_id-ne[string]$record.cube_id){Deny 'memory_share_record_binding_mismatch'}
      if([string]$share.source_agent_id-ne[string]$record.created_by_agent_id-or[string]$share.target_agent_id-ne$AgentId){Deny 'memory_share_agent_binding_mismatch'}
      if([string]$share.task_id-ne$TaskId-or[string]$share.tenant_id-ne$TenantId-or[string]$share.organization_id-ne$OrganizationId-or[string]$share.project_id-ne$ProjectId-or[string]$share.role_id-ne$RoleId){Deny 'memory_share_scope_mismatch'}
      if($share.can_delegate-ne$false-or$share.execution_authority-ne$false-or$share.permission_authority-ne$false){Deny 'memory_share_authority_boundary_failed'}
      if(Test-Path -LiteralPath $shareRevocationPath){foreach($line in @(Get-Content -LiteralPath $shareRevocationPath -Encoding UTF8)){if([string]::IsNullOrWhiteSpace($line)){continue};try{$sr=$line|ConvertFrom-Json;if([string]$sr.share_grant_id-eq[string]$share.share_grant_id){Deny 'memory_share_grant_revoked';break}}catch{Deny 'memory_share_revocation_ledger_invalid';break}}}
    }
  }
}
if($violations.Count){Emit ([ordered]@{status='denied';memory_id=[string]$record.memory_id;effective_status=$effective;violations=@($violations);contents_returned=$false;full_memory_returned=$false;external_calls=$false}) 1}
$audit=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
try{& $audit -EventType memory_read_requested -Decision allow -TenantId $TenantId -OrganizationId $OrganizationId -UserId ([string]$grant.employee_id) -AgentId $AgentId -AgentVersion ([string]$grant.agent_version) -TaskId $TaskId -GrantId ([string]$grant.grant_id) -TraceId ([string]$grant.trace_id) -PolicyVersion '2.14.0' -DataRefs @($memoryRef,$cubeRef) -EvidenceRefs (@($record.source_refs)+@([string]$record.audit_chain_ref)) -PassThru|Out-Null}catch{Emit ([ordered]@{status='denied';reason='memory_read_audit_failed';contents_returned=$false;external_calls=$false}) 1}
Emit ([ordered]@{status='allowed';task_id=$TaskId;grant_id=[string]$grant.grant_id;memory_pack=[ordered]@{memory_id=[string]$record.memory_id;memory_type=[string]$record.memory_type;memory_layer=[string]$record.memory_layer;cube_id=[string]$record.cube_id;content_ref=[string]$record.content_ref;scope=[string]$record.scope;source_refs=@($record.source_refs);record_version=[string]$record.record_version;owner_id=[string]$record.owner_id;audit_chain_ref=[string]$record.audit_chain_ref;classification=[string]$record.classification;confidence=[double]$record.confidence;expires_at=[string]$record.expires_at;visibility=[string]$record.visibility};effective_status=$effective;contents_returned=$true;full_memory_returned=$false;raw_content_returned=$false;permission_expanded=$false;skill_execution_authorized=$false;external_calls=$false})
