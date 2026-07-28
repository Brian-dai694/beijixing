<##
.SYNOPSIS
  Runs the Enterprise L2 Broker gate before the offline advertising diagnostic.
.DESCRIPTION
  Binds identity, device, project, Grant, Attestation, and data scope before
  reading a local snapshot. It never calls a Provider, MCP server, or business
  API. The persisted receipt contains metadata only; raw rows are not stored.
##>
param(
  [Parameter(Mandatory=$true)][string]$InputPath,
  [Parameter(Mandatory=$true)][string]$TenantId,
  [Parameter(Mandatory=$true)][string]$OrganizationId,
  [Parameter(Mandatory=$true)][string]$EmployeeId,
  [Parameter(Mandatory=$true)][string]$DeviceId,
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [Parameter(Mandatory=$true)][string]$CostCenter,
  [Parameter(Mandatory=$true)][string]$AgentId,
  [Parameter(Mandatory=$true)][string]$AgentVersion,
  [Parameter(Mandatory=$true)][string]$TraceId,
  [string]$GrantPath='',
  [ValidateSet('T0','T1','T2','T3','T4')][string]$AgentTrust='T1',
  [ValidateSet('missing','verified','expired','revoked')][string]$AttestationStatus='missing',
  [string]$ReceiptPath='',
  [switch]$PassThru
)

$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$taskGate=Join-Path $PSScriptRoot 'invoke-enterprise-task-gate.ps1'
$diagnostic=Join-Path $PSScriptRoot 'invoke-enterprise-ad-diagnostic-v1.ps1'
$powerShellResolver=Join-Path $PSScriptRoot 'resolve-enterprise-powershell.ps1';. $powerShellResolver;$powerShellCommand=Get-EnterprisePowerShellCommand
$grantRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\delegation-grants')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$revocationPath=Join-Path $projectRoot '.qianlima\run-traces\grant-revocations.jsonl'
$receiptRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\enterprise-receipts')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar

function Emit([object]$Value,[int]$Code=0) {
  if($PassThru){$Value|ConvertTo-Json -Depth 15}else{$Value|Format-List}
  if($Code -ne 0){exit $Code}
}
function Invoke-Json([string]$Path,[string[]]$ScriptArgs) {
  $lines=@(& $powerShellCommand -NoProfile -ExecutionPolicy Bypass -File $Path @ScriptArgs 2>&1)
  $code=$LASTEXITCODE; $text=($lines|ForEach-Object{$_.ToString()})-join "`n"; $value=$null
  $start=$text.IndexOf('{'); $end=$text.LastIndexOf('}')
  if($start -ge 0 -and $end -gt $start){try{$value=$text.Substring($start,$end-$start+1)|ConvertFrom-Json}catch{}}
  return [pscustomobject]@{exit_code=$code;text=$text;value=$value}
}
function Get-DiagnosticResultHash([object]$Diagnostic) {
  $cards = @($Diagnostic.action_cards | ForEach-Object {
    @($_.campaign_id, $_.target_id, $_.issue, $_.recommendation, $_.evidence.source_hash, $_.evidence.data_as_of) -join '|'
  } | Sort-Object)
  $canonical = @("task_id=$($Diagnostic.task_id)", "grant_id=$($Diagnostic.grant_id)", "status=$($Diagnostic.status)", "source_hash=$($Diagnostic.source_hash)", "data_as_of=$($Diagnostic.data_as_of)", 'cards=', ($cards -join "`n")) -join "`n"
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

if(-not(Test-Path -LiteralPath $InputPath -PathType Leaf)){Emit ([ordered]@{status='blocked';reason='input_not_found';external_calls=$false;execution_authorized=$false}) 1}
try{$input=Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{Emit ([ordered]@{status='blocked';reason='invalid_input';external_calls=$false;execution_authorized=$false}) 1}
if([string]::IsNullOrWhiteSpace([string]$input.task_id)){Emit ([ordered]@{status='blocked';reason='task_id_required';external_calls=$false;execution_authorized=$false}) 1}
if([string]$input.data_scope -notin @('advertising','advertising_snapshot')){Emit ([ordered]@{status='blocked';reason='advertising_scope_required';external_calls=$false;execution_authorized=$false}) 1}
if([string]::IsNullOrWhiteSpace($GrantPath)){Emit ([ordered]@{status='blocked';reason='governed_grant_path_required';external_calls=$false;execution_authorized=$false}) 1}
try{$grantFull=(Resolve-Path -LiteralPath $GrantPath -ErrorAction Stop).Path}catch{Emit ([ordered]@{status='blocked';reason='grant_not_found';external_calls=$false;execution_authorized=$false}) 1}
if(-not $grantFull.StartsWith($grantRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='blocked';reason='grant_outside_governed_root';external_calls=$false;execution_authorized=$false}) 1}
try{$grant=Get-Content -LiteralPath $grantFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Emit ([ordered]@{status='blocked';reason='grant_invalid';external_calls=$false;execution_authorized=$false}) 1}
if($null -eq $grant -or [string]$grant.agent_id -ne $AgentId -or [string]$grant.agent_version -ne $AgentVersion){Emit ([ordered]@{status='blocked';reason='grant_agent_or_version_mismatch';external_calls=$false;execution_authorized=$false}) 1}
if([string]$grant.task_id -ne [string]$input.task_id){Emit ([ordered]@{status='blocked';reason='grant_task_mismatch';external_calls=$false;execution_authorized=$false}) 1}
if(Test-Path -LiteralPath $revocationPath -PathType Leaf){
  $revoked=$false
  try {
    foreach($line in @(Get-Content -LiteralPath $revocationPath -Encoding UTF8)) {
      if([string]::IsNullOrWhiteSpace($line)){continue}
      $record=$line|ConvertFrom-Json
      if([string]$record.grant_id -eq [string]$grant.grant_id){$revoked=$true;break}
    }
  } catch { Emit ([ordered]@{status='blocked';reason='grant_revocation_ledger_invalid';external_calls=$false;execution_authorized=$false}) 1 }
  if($revoked){Emit ([ordered]@{status='blocked';reason='grant_revoked';grant_id=[string]$grant.grant_id;external_calls=$false;execution_authorized=$false;process_started=$false}) 1}
}

$gateArgs=@('-RequestedLevel','L2','-ClassificationEdition','enterprise','-DataClassification','internal_sanitized','-OrganizationalScope','project','-ActionType','analysis','-TenantId',$TenantId,'-OrganizationId',$OrganizationId,'-EmployeeId',$EmployeeId,'-DeviceId',$DeviceId,'-ProjectId',$ProjectId,'-CostCenter',$CostCenter,'-AgentTrust',$AgentTrust,'-GrantId',[string]$grant.grant_id,'-AttestationStatus',$AttestationStatus,'-PassThru')
$gate=Invoke-Json $taskGate $gateArgs
if($gate.exit_code -ne 0 -or $null -eq $gate.value -or $gate.value.status -ne 'allowed'){Emit ([ordered]@{status='blocked';reason='enterprise_l2_gate_denied';task_gate=$gate.value;external_calls=$false;execution_authorized=$false}) 1}

$diagnosticArgs=@('-InputPath',$InputPath,'-ExpectedTaskId',[string]$input.task_id,'-GrantPath',$GrantPath,'-PassThru')
$diagnosticResult=Invoke-Json $diagnostic $diagnosticArgs
if($diagnosticResult.exit_code -ne 0 -or $null -eq $diagnosticResult.value){Emit ([ordered]@{status='blocked';reason='diagnostic_denied';diagnostic=$diagnosticResult.value;external_calls=$false;execution_authorized=$false}) 1}
$result=$diagnosticResult.value
$diagnosticResultHash = Get-DiagnosticResultHash $result
$receiptId='receipt-ad-diagnostic-v1-'+[Guid]::NewGuid().ToString('n')
$receipt=[ordered]@{
  schema_version=1; receipt_id=$receiptId; receipt_type='enterprise_readonly_diagnostic'
  task_id=[string]$input.task_id; grant_id=[string]$grant.grant_id; agent_id=$AgentId
  agent_version=$AgentVersion; trace_id=$TraceId
  tenant_id=$TenantId; organization_id=$OrganizationId; employee_id=$EmployeeId; device_id=$DeviceId; project_id=$ProjectId
  source_hash=[string]$result.source_hash; diagnostic_result_hash=$diagnosticResultHash; data_scope=[string]$input.data_scope; data_time_range=[string]$input.as_of
  method_ref='beijixing-enterprise-amazon-ad-diagnostic-v1'; task_gate='L2_allowed'
  action_card_count=@($result.action_cards).Count; verification_status='pending_review'
  external_calls=$false; execution_authorized=$false; write_performed=$false; raw_rows_recorded=$false
  next_state=if(@($result.action_cards).Count -gt 0){'human_review'}else{'completed'}
  created_at=(Get-Date).ToUniversalTime().ToString('o')
}
if([string]::IsNullOrWhiteSpace($ReceiptPath)){$ReceiptPath=Join-Path $receiptRoot "$receiptId.json"}
$receiptFull=[IO.Path]::GetFullPath($ReceiptPath)
if(-not $receiptFull.StartsWith($receiptRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='blocked';reason='receipt_outside_governed_root';external_calls=$false;execution_authorized=$false}) 1}
if(-not(Test-Path -LiteralPath (Split-Path -Parent $receiptFull) -PathType Container)){New-Item -ItemType Directory -Path (Split-Path -Parent $receiptFull) -Force|Out-Null}
[IO.File]::WriteAllText($receiptFull,($receipt|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
$auditScript=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl'
$auditArgs=@('-EventType','tool_allowed','-Decision','allow','-TenantId',$TenantId,'-OrganizationId',$OrganizationId,'-UserId',$EmployeeId,'-AgentId',$AgentId,'-AgentVersion',$AgentVersion,'-TaskId',[string]$input.task_id,'-GrantId',[string]$grant.grant_id,'-TraceId',$TraceId,'-PolicyVersion','2.14.0','-DataRefs',('snapshot:sha256:'+[string]$result.source_hash),'-ArtifactRefs',('receipt:'+ $receiptId),'-EvidenceRefs',('receipt:'+ $receiptId),'-RunnerAttestationRef','attestation:verified','-OutputPath',$auditPath)
& $powerShellCommand -NoProfile -ExecutionPolicy Bypass -File $auditScript @auditArgs | Out-Null
if($LASTEXITCODE-ne 0){Emit ([ordered]@{status='blocked';reason='audit_event_write_failed';receipt=$receipt;external_calls=$false;execution_authorized=$false;write_performed=$false}) 1}
Emit ([ordered]@{status=[string]$result.status;broker='beijixing_enterprise';task_gate=$gate.value;diagnostic=$result;receipt=$receipt;receipt_path=$receiptFull;audit_event_path=$auditPath;external_calls=$false;execution_authorized=$false;write_performed=$false;process_started=$false}) 0
