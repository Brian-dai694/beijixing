param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$contractPath = Join-Path $PSScriptRoot 'goal-work-graph-contract.json'
$eventsPath = Join-Path $PSScriptRoot 'event-contract.json'
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$events = Get-Content -LiteralPath $eventsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$violations = [System.Collections.Generic.List[string]]::new()

function Require-Value([object]$Value, [string]$Name) {
  if ($null -eq $Value -or ([string]$Value -eq '')) { [void]$violations.Add("missing_$Name") }
}

Require-Value $contract.contract_id 'contract_id'
Require-Value $contract.principle 'principle'
foreach ($field in @('goal_id','business_owner_id','success_metrics','deadline','budget_ref')) {
  if (@($contract.goal.required_fields) -notcontains $field) { [void]$violations.Add("goal_field_missing_$field") }
}
foreach ($field in @('work_order_ref','completion_rule','risk_level')) {
  if (@($contract.work_node.required_fields) -notcontains $field) { [void]$violations.Add("work_node_field_missing_$field") }
}
if ([string]$contract.work_node.completion_rule -notmatch 'independent_verification') { [void]$violations.Add('independent_verification_not_required') }
if (@($contract.manager_projection.allowed_sources) -contains 'agent_status_message') { [void]$violations.Add('unverified_agent_status_allowed') }
if (@($contract.manager_projection.prohibited_fields) -notcontains 'unverified_completion_claim') { [void]$violations.Add('unverified_completion_not_prohibited') }
if (@($contract.global_invariants | Where-Object { [string]$_ -match 'direct communication remains prohibited' }).Count -eq 0) { [void]$violations.Add('direct_a2a_prohibition_missing') }
if (@($contract.compounding_loop.required_gates) -notcontains 'independent_verification') { [void]$violations.Add('improvement_independent_verification_missing') }
foreach ($eventType in @($contract.event_requirements)) {
  if (@($events.allowed_events) -notcontains $eventType) { [void]$violations.Add("event_contract_missing_$eventType") }
}
if (@($events.scope_field_rules.goal_events.required_fields) -notcontains 'goal_id') { [void]$violations.Add('goal_event_goal_id_missing') }
if (@($events.scope_field_rules.goal_events.required_fields) -notcontains 'business_owner_id') { [void]$violations.Add('goal_event_owner_missing') }
if (@($events.scope_field_rules.goal_work_node_events.required_fields) -notcontains 'work_order_ref') { [void]$violations.Add('goal_node_work_order_missing') }
if (@($events.scope_field_rules.goal_projection_events.required_fields) -notcontains 'goal_id') { [void]$violations.Add('goal_projection_goal_id_missing') }
if (@($events.scope_field_rules.goal_projection_events.required_fields) -notcontains 'evidence_refs') { [void]$violations.Add('goal_projection_evidence_missing') }
if (@($events.required_fields) -contains 'task_id') { [void]$violations.Add('goal_events_forced_to_fake_task_id') }

$result = [PSCustomObject]@{
  status = if ($violations.Count -eq 0) { 'passed' } else { 'failed' }
  contract_id = $contract.contract_id
  violations = @($violations)
}
if ($PassThru) { $result | ConvertTo-Json -Depth 4 } else { $result | Format-List }
if ($violations.Count -gt 0) { throw "Goal work graph contract regression failed: $($violations -join ', ')" }
