<##
.SYNOPSIS
  Issues a short-lived, read-only Grant for Amazon advertising diagnostics.
.DESCRIPTION
  This is the V1 Enterprise Grant issuer. It admits only an approved Agent
  registry entry and emits one task-bound L2 Grant. It never grants network,
  write, secret, or delegation authority.
##>
param(
  [Parameter(Mandatory=$true)][string]$GrantId,
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$TenantId,
  [Parameter(Mandatory=$true)][string]$OrganizationId,
  [Parameter(Mandatory=$true)][string]$EmployeeId,
  [Parameter(Mandatory=$true)][string]$DeviceId,
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [Parameter(Mandatory=$true)][string]$CostCenter,
  [Parameter(Mandatory=$true)][string]$AgentId,
  [Parameter(Mandatory=$true)][string]$AgentVersion,
  [Parameter(Mandatory=$true)][string]$TraceId,
  [ValidateSet('missing','verified','expired','revoked')][string]$AttestationStatus='missing',
  [ValidateRange(1,30)][int]$ExpiresMinutes=10,
  [string]$RegistryPath='',
  [string]$OutputPath='',
  [switch]$PassThru
)

$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$grantRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\delegation-grants')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$powerShellResolver=Join-Path $PSScriptRoot 'resolve-enterprise-powershell.ps1';. $powerShellResolver;$powerShellCommand=Get-EnterprisePowerShellCommand
function Emit([object]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 15}else{$Value|Format-List};if($Code-ne 0){exit $Code}}
if([string]::IsNullOrWhiteSpace($RegistryPath)){$RegistryPath=Join-Path $PSScriptRoot 'agent-registry.example.json'}
try{$registry=Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{Emit ([ordered]@{status='blocked';reason='agent_registry_invalid';execution_authorized=$false}) 1}
$agent=@($registry.agents|Where-Object{$_.agent_id-eq$AgentId-and$_.agent_version-eq$AgentVersion}|Select-Object -First 1)
if($agent.Count-ne 1){Emit ([ordered]@{status='blocked';reason='agent_not_registered_or_version_mismatch';agent_id=$AgentId;execution_authorized=$false}) 1}
if($agent.status-ne'approved'){Emit ([ordered]@{status='blocked';reason='agent_not_approved';agent_id=$AgentId;execution_authorized=$false}) 1}
if(@($agent.capabilities)-notcontains'read_advertising'-or@($agent.allowed_data_scopes)-notcontains'advertising'){Emit ([ordered]@{status='blocked';reason='agent_capability_scope_denied';agent_id=$AgentId;execution_authorized=$false}) 1}
if($agent.risk_ceiling-ne'L2'-or$agent.network-ne'none'-or$agent.write_access-ne'none'-or$agent.can_delegate-ne$false){Emit ([ordered]@{status='blocked';reason='agent_registry_boundary_failed';agent_id=$AgentId;execution_authorized=$false}) 1}
if($AttestationStatus-ne'verified'){Emit ([ordered]@{status='blocked';reason='verified_attestation_required';agent_id=$AgentId;execution_authorized=$false}) 1}
foreach($field in @(@{n='grant_id';v=$GrantId},@{n='task_id';v=$TaskId},@{n='tenant_id';v=$TenantId},@{n='organization_id';v=$OrganizationId},@{n='employee_id';v=$EmployeeId},@{n='device_id';v=$DeviceId},@{n='project_id';v=$ProjectId},@{n='cost_center';v=$CostCenter},@{n='trace_id';v=$TraceId})){if([string]::IsNullOrWhiteSpace($field.v)){Emit ([ordered]@{status='blocked';reason="$($field.n)_required";execution_authorized=$false}) 1}}
if($GrantId-match'[/\\]|\.\.' ){Emit ([ordered]@{status='blocked';reason='unsafe_grant_id';execution_authorized=$false}) 1}
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $grantRoot "$GrantId.json"}
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if(-not$outputFull.StartsWith($grantRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='blocked';reason='grant_output_outside_governed_root';execution_authorized=$false}) 1}
if(Test-Path -LiteralPath $outputFull){Emit ([ordered]@{status='blocked';reason='grant_already_exists';grant_id=$GrantId;execution_authorized=$false}) 1}
if(-not(Test-Path -LiteralPath (Split-Path -Parent $outputFull) -PathType Container)){New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force|Out-Null}
$grant=[ordered]@{
  schema_version=1;contract_type='beijixing_enterprise_task_grant';grant_id=$GrantId;status='issued';task_id=$TaskId
  tenant_id=$TenantId;organization_id=$OrganizationId;employee_id=$EmployeeId;device_id=$DeviceId;project_id=$ProjectId;cost_center=$CostCenter
  agent_id=$AgentId;agent_version=$AgentVersion;trace_id=$TraceId;data_scope=@('advertising');data_refs=@('advertising:snapshot')
  allowed_operations=@('read_advertising');allowed_tools=@('enterprise_ad_diagnostic_v1');risk_ceiling='L2'
  budget=[ordered]@{max_steps=3;max_tool_calls=1;max_evidence_items=20};expires_at=(Get-Date).ToUniversalTime().AddMinutes($ExpiresMinutes).ToString('o')
  network_access='none';write_access='none';can_delegate=$false;attestation_status='verified';revocable=$true;issued_by='beijixing_broker'
}
[IO.File]::WriteAllText($outputFull,($grant|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
$audit=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1';$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl'
$auditArgs=@('-EventType','grant_issued','-Decision','allow','-TenantId',$TenantId,'-OrganizationId',$OrganizationId,'-UserId',$EmployeeId,'-AgentId',$AgentId,'-AgentVersion',$AgentVersion,'-TaskId',$TaskId,'-GrantId',$GrantId,'-TraceId',$TraceId,'-PolicyVersion','2.14.0','-DataRefs','advertising:snapshot','-EvidenceRefs',('grant:'+ $GrantId),'-RunnerAttestationRef','attestation:verified','-OutputPath',$auditPath)
& $powerShellCommand -NoProfile -ExecutionPolicy Bypass -File $audit @auditArgs|Out-Null
if($LASTEXITCODE-ne 0){Emit ([ordered]@{status='blocked';reason='grant_audit_write_failed';grant_id=$GrantId;execution_authorized=$false}) 1}
Emit ([ordered]@{status='issued';grant=$grant;grant_path=$outputFull;audit_event_path=$auditPath;execution_authorized=$false;network_opened=$false;write_performed=$false;external_calls=$false}) 0
