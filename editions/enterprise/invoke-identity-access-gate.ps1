<#
.SYNOPSIS
  Validates an enterprise user and role assignment without changing identity or access.
#>
param([Parameter(Mandatory=$true)][string]$RequestJson,[switch]$PassThru)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$request=$RequestJson|ConvertFrom-Json
$users=Get-Content -LiteralPath (Join-Path $root 'user-management-policy.json') -Raw -Encoding UTF8|ConvertFrom-Json
$roles=Get-Content -LiteralPath (Join-Path $root 'organization-role-templates.json') -Raw -Encoding UTF8|ConvertFrom-Json
$contract=Get-Content -LiteralPath (Join-Path $root 'role-assignment-contract.json') -Raw -Encoding UTF8|ConvertFrom-Json
$reasons=[System.Collections.Generic.List[string]]::new()
function Missing([object]$Object,[string]$Name){$p=$Object.PSObject.Properties[$Name];return $null-eq$p-or$null-eq$p.Value-or[string]::IsNullOrWhiteSpace([string]$p.Value)}
foreach($field in @($users.user_required_fields)){if(Missing $request.user $field){[void]$reasons.Add("missing_user_$field")}}
foreach($field in @($contract.required_fields)){if(Missing $request.assignment $field){[void]$reasons.Add("missing_assignment_$field")}}
$user=$request.user;$assignment=$request.assignment
if($user.status-notin@($users.states)){[void]$reasons.Add('invalid_user_status')}
if($user.status-ne'active'){[void]$reasons.Add('user_not_active')}
if($user.organization_id-ne$assignment.organization_id){[void]$reasons.Add('organization_mismatch')}
if($assignment.requested_by-eq$assignment.approved_by){[void]$reasons.Add('self_approval_denied')}
$catalog=if($assignment.role_type-eq'governance'){@($roles.governance_roles)}elseif($assignment.role_type-eq'business'){@($roles.business_roles)}else{@();[void]$reasons.Add('invalid_role_type')}
if(@($catalog.id)-notcontains$assignment.role_id){[void]$reasons.Add('unknown_role_id')}
if($assignment.scope_type-notin@($contract.scope_types)){[void]$reasons.Add('invalid_scope_type')}
if(@($assignment.scope_ids).Count-eq0){[void]$reasons.Add('scope_required')}
if($assignment.temporary-eq$true-and(Missing $assignment 'expires_at')){[void]$reasons.Add('temporary_expiry_required')}
if($assignment.role_id-in@($contract.privileged_governance_roles)-and(Missing $assignment 'second_approved_by')){[void]$reasons.Add('privileged_second_approval_required')}
if($assignment.second_approved_by-in@($assignment.requested_by,$assignment.approved_by)){[void]$reasons.Add('privileged_approvers_must_be_distinct')}
$status=if($reasons.Count-eq0){'eligible_for_role_assignment'}else{'blocked'}
$result=[PSCustomObject]@{status=$status;user_id=$user.user_id;role_id=$assignment.role_id;scope_ids=@($assignment.scope_ids);runtime_authority='none';agent_trust_changed=$false;data_access_changed=$false;write_access_changed=$false;next_action=if($status-eq'eligible_for_role_assignment'){'record_append_only_assignment_event_then_recalculate_scope'}else{'correct_request_and_resubmit'};reasons=@($reasons);external_calls=$false;changes_applied=$false}
if($PassThru){$result|ConvertTo-Json -Depth 8}else{$result|Format-List}
if($reasons.Count-gt0-and-not$PassThru){exit 1}
