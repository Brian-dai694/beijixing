param(
  [Parameter(Mandatory)][ValidateSet('deterministic_tool','on_demand_knowledge','independent_delegation')][string]$Class,
  [bool]$HasIndependentGoal = $false,
  [bool]$HasMinimumEvidencePack = $false,
  [bool]$HasChildWorkOrder = $false,
  [bool]$HasChildGrant = $false,
  [bool]$InheritsParentPermissions = $false,
  [bool]$RequestsWriteExternalSendOrBudgetChange = $false,
  [bool]$HasNewHumanApproval = $false,
  [switch]$PassThru
)

$reasons = [System.Collections.Generic.List[string]]::new()
switch ($Class) {
  'deterministic_tool' {
    if ($HasIndependentGoal) { $reasons.Add('deterministic_tool_cannot_have_independent_goal') }
    if ($HasChildWorkOrder -or $HasChildGrant) { $reasons.Add('deterministic_tool_cannot_delegate') }
  }
  'on_demand_knowledge' {
    if (-not $HasMinimumEvidencePack) { $reasons.Add('minimum_evidence_pack_required') }
    if ($HasIndependentGoal) { $reasons.Add('independent_goal_requires_independent_delegation') }
  }
  'independent_delegation' {
    if (-not $HasIndependentGoal) { $reasons.Add('independent_value_required') }
    if (-not $HasChildWorkOrder) { $reasons.Add('child_work_order_required') }
    if (-not $HasChildGrant) { $reasons.Add('child_grant_required') }
    if ($InheritsParentPermissions) { $reasons.Add('parent_permission_inheritance_denied') }
  }
}
if ($RequestsWriteExternalSendOrBudgetChange -and -not $HasNewHumanApproval) {
  $reasons.Add('new_human_approval_required')
}

$result = [PSCustomObject]@{
  allowed = ($reasons.Count -eq 0)
  class = $Class
  reasons = @($reasons)
  external_calls = $false
  permissions_granted = $false
}
if ($PassThru) { $result | ConvertTo-Json -Depth 5 } else { $result }
if (-not $result.allowed) { exit 2 }
