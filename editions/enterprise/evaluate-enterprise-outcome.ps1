[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [string]$PolicyPath = '',
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PolicyPath)) { $PolicyPath = Join-Path $PSScriptRoot 'enterprise-outcome-evaluation-policy.json' }
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 12 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
function Require([object]$Value, [string]$Name) { if ($null -eq $Value -or ([string]$Value).Trim().Length -eq 0) { throw "outcome_evaluation_missing_$Name" } }
function Score([object]$Value, [string]$Name) { if ($null -eq $Value) { throw "outcome_evaluation_missing_metric:$Name" }; $number = [double]$Value; if ($number -lt 0 -or $number -gt 1) { throw "outcome_evaluation_metric_out_of_range:$Name" }; $number }

$policy = Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($policy.status -ne 'active') { Emit ([ordered]@{ status = 'blocked'; reason = 'outcome_evaluation_policy_not_active'; execution_authorized = $false }) 1 }
$input = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($field in @($policy.required_input)) { Require $input.$field $field }
if ($input.grant_checked -ne $true -or $input.policy_gate_checked -ne $true) { Emit ([ordered]@{ status = 'blocked'; reason = 'grant_and_policy_gate_required_before_evaluation'; execution_authorized = $false }) 1 }
if (@($input.observed_evidence_refs).Count -eq 0) { Emit ([ordered]@{ status = 'blocked'; reason = 'observed_evidence_required'; execution_authorized = $false }) 1 }

$metrics = $input.metrics
$score = 0.0
foreach ($name in @($policy.dimensions.psobject.Properties.Name)) {
    $value = Score $metrics.$name $name
    $score += $value * [double]$policy.dimensions.$name.weight
}
$constraintsPassed = $true
foreach ($name in @($policy.hard_constraints)) { if ($input.constraints.$name -ne $true) { $constraintsPassed = $false } }
if (-not $constraintsPassed) { $route = 'freeze_and_escalate'; $eventType = 'outcome_evaluation_escalated'; $decision = 'freeze' }
elseif ($score -ge [double]$policy.routing.recommendation_ready_min_score) { $route = 'recommendation_ready'; $eventType = 'outcome_evaluation_scored'; $decision = 'accept' }
elseif ($score -ge [double]$policy.routing.human_review_min_score) { $route = 'human_review_required'; $eventType = 'outcome_evaluation_escalated'; $decision = 'pause' }
else { $route = 'freeze_and_escalate'; $eventType = 'outcome_evaluation_escalated'; $decision = 'freeze' }

$audit = Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
$auditEvent = & $audit -EventType $eventType -Decision $decision -TenantId $input.tenant_id -OrganizationId $input.organization_id -UserId $input.user_id -AgentId $input.agent_id -AgentVersion $input.agent_version -TaskId $input.task_id -GrantId $input.grant_id -TraceId ('outcome-evaluation-' + $input.evaluation_id) -PolicyVersion $policy.policy_version -PolicyRef ('policy://' + $policy.policy_id) -DecisionReason ('route=' + $route + '; score=' + $score.ToString('F4', [Globalization.CultureInfo]::InvariantCulture)) -DataRefs @('evaluation_metadata_only') -ArtifactRefs @('evaluation://' + $input.evaluation_id) -EvidenceRefs @($input.observed_evidence_refs) -VerificationRef $input.expected_outcome -ResponsibleParty $input.user_id -PassThru | ConvertFrom-Json

Emit ([ordered]@{
    status = 'evaluated'; evaluation_id = $input.evaluation_id; candidate_id = $input.candidate_id; policy_id = $policy.policy_id; policy_version = $policy.policy_version
    expected_outcome = $input.expected_outcome; observed_evidence_refs = @($input.observed_evidence_refs); score = [Math]::Round($score, 4)
    constraints_passed = $constraintsPassed; route = $route; audit_event_id = $auditEvent.event_id
    action_gate_required = $true; execution_authorized = $false; raw_customer_content_stored = $false
})
