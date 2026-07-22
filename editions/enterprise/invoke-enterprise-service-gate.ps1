<# .SYNOPSIS Offline gate for UI, MCP, and scheduled Agent access to enterprise business services. #>
param(
  [ValidateSet('ui_user','mcp_agent','scheduled_agent')][string]$CallerType,
  [ValidateSet('read','prepare_write','execute_write')][string]$Operation,
  [ValidateSet('L1','L2','L3','L4')][string]$RiskLevel,
  [string]$TaskId='', [string]$GrantId='',
  [string]$OrganizationId='', [string]$ProjectId='', [string]$StoreId='', [string]$Marketplace='', [string]$ProductLine='',
  [string]$GrantOrganizationId='', [string]$GrantProjectId='', [string]$GrantStoreId='',
  [string]$ServiceIdentityId='', [string]$ScheduleId='', [string]$SecretReference='',
  [switch]$OwnershipVerified, [switch]$OAuthValidated, [switch]$GrantActive,
  [switch]$BudgetAvailable, [switch]$AdapterAllowlisted, [switch]$PassThru
)
$ErrorActionPreference='Stop'
$reasons=[System.Collections.Generic.List[string]]::new()
foreach($item in @(@('task_id',$TaskId),@('grant_id',$GrantId),@('organization_id',$OrganizationId),@('project_id',$ProjectId),@('store_id',$StoreId),@('marketplace',$Marketplace),@('product_line',$ProductLine))){
  if([string]::IsNullOrWhiteSpace($item[1])){[void]$reasons.Add("missing_$($item[0])")}
}
if(-not $OwnershipVerified){[void]$reasons.Add('project_ownership_required')}
if(-not $GrantActive){[void]$reasons.Add('active_task_grant_required')}
if(-not $BudgetAvailable){[void]$reasons.Add('budget_required')}
if(-not $AdapterAllowlisted){[void]$reasons.Add('approved_adapter_required')}
if($OrganizationId-ne$GrantOrganizationId-or$ProjectId-ne$GrantProjectId-or$StoreId-ne$GrantStoreId){[void]$reasons.Add('grant_scope_mismatch')}
if($CallerType-eq'mcp_agent'-and-not $OAuthValidated){[void]$reasons.Add('mcp_oauth_required')}
if($CallerType-eq'scheduled_agent'){
  if([string]::IsNullOrWhiteSpace($ServiceIdentityId)){[void]$reasons.Add('scheduled_service_identity_required')}
  if([string]::IsNullOrWhiteSpace($ScheduleId)){[void]$reasons.Add('schedule_id_required')}
}
if([string]::IsNullOrWhiteSpace($SecretReference)-or$SecretReference-notmatch'^secretref:[A-Za-z0-9._/-]+$'){[void]$reasons.Add('valid_secret_reference_required')}
if($Operation-eq'prepare_write'-and$RiskLevel-ne'L4'){[void]$reasons.Add('write_candidate_must_be_L4')}
if($Operation-eq'execute_write'){[void]$reasons.Add('business_write_disabled_this_release')}
$status='blocked';$next='freeze_and_return_to_broker'
if($reasons.Count-eq 0){
  if($Operation-eq'prepare_write'){$status='needs_human';$next='human_review_candidate_no_execution'}
  else{$status='service_plan_allowed';$next='issue_single_call_adapter_plan'}
}
$result=[pscustomobject]@{status=$status;caller_type=$CallerType;task_id=$TaskId;grant_id=$GrantId;project_id=$ProjectId;operation=$Operation;oauth_is_task_authority=$false;execution_authorized=$false;external_calls=$false;processes_started=$false;files_written=$false;permissions_granted=$false;cost_receipt_required=$true;next_step=$next;reasons=@($reasons)}
if($PassThru){$result|ConvertTo-Json -Depth 6}else{$result|Format-List}
if($status-eq'blocked'){exit 1}