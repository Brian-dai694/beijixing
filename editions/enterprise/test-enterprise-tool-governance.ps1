param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$register = Join-Path $PSScriptRoot 'new-enterprise-tool-registration.ps1'
$state = Join-Path $PSScriptRoot 'set-enterprise-tool-state.ps1'
$gate = Join-Path $PSScriptRoot 'invoke-enterprise-tool-gate.ps1'
$feedback = Join-Path $PSScriptRoot 'new-enterprise-tool-feedback-candidate.ps1'
$trial = Join-Path $PSScriptRoot 'new-enterprise-tool-trial-receipt.ps1'
$verify = Join-Path $PSScriptRoot 'verify-enterprise-tool-release.ps1'
$trust = Join-Path $PSScriptRoot 'assess-enterprise-tool-trust.ps1'
$rollback = Join-Path $PSScriptRoot 'rollback-enterprise-tool-version.ps1'
$suffix = [Guid]::NewGuid().ToString('n')
$passportPath = Join-Path $root ('.qianlima/run-traces/enterprise-tools/registry/test-' + $suffix + '.json')
$hash = 'sha256:' + ('a' * 64)
function RunJson([string]$Script, [string[]]$Arguments) {
  $raw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1)
  [pscustomobject]@{ code = $LASTEXITCODE; text = (($raw | ForEach-Object { $_.ToString() }) -join "`n") }
}
function Has([object]$Run, [string]$Text) { return ($Run.code -ne 0 -and $Run.text -match $Text) }
$cases = [System.Collections.Generic.List[object]]::new()
$registered = RunJson $register @('-ToolId', 'test_read_tool', '-ToolVersion', '1.0.0', '-OwnerId', 'owner_1', '-TenantId', 'tenant_1', '-OrganizationId', 'org_1', '-ProjectId', 'project_1', '-Purpose', 'read-only test tool', '-ApplicableScenarios', 'finance lookup', '-InputSchemaRef', 'sha256:input', '-OutputSchemaRef', 'sha256:output', '-CapabilityBoundary', 'read:internal_sanitized', '-AccessPermissions', 'read:assigned_scope', '-DataClass', 'internal_sanitized', '-DeclaredDependencies', 'runtime://approved', '-RiskLevel', 'L2', '-CostModel', 'fixed:1', '-AuditRequirements', 'policy_reason;verification_ref', '-RollbackRef', 'sha256:rollback', '-ArtifactRef', 'sha256:artifact', '-IntegrityHash', $hash, '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-OutputPath', $passportPath, '-PassThru')
$cases.Add([pscustomobject]@{ name = 'tool_registration_is_candidate_only'; passed = ($registered.code -eq 0 -and $registered.text -match 'production_authority.*false' -and (Test-Path -LiteralPath $passportPath)) })
$static = RunJson $state @('-PassportPath', $passportPath, '-TargetState', 'static_checked', '-EvidenceRef', 'sha256:static', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-ApproverId', 'owner_1', '-PassThru')
$cases.Add([pscustomobject]@{ name = 'lifecycle_requires_ordered_promotion'; passed = ($static.code -eq 0 -and $static.text -match 'static_checked') })
$directActive = RunJson $state @('-PassportPath', $passportPath, '-TargetState', 'active', '-EvidenceRef', 'sha256:bad-order', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-ApproverId', 'owner_1', '-PassThru')
$cases.Add([pscustomobject]@{ name = 'direct_activation_is_blocked'; passed = (Has $directActive 'invalid_tool_state_transition') })
$sandbox = RunJson $state @('-PassportPath', $passportPath, '-TargetState', 'sandboxed', '-EvidenceRef', 'sha256:sandbox', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-ApproverId', 'owner_1', '-PassThru')
$approved = RunJson $state @('-PassportPath', $passportPath, '-TargetState', 'approved', '-EvidenceRef', 'sha256:approval', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-ApproverId', 'owner_1', '-PassThru')
$active = RunJson $state @('-PassportPath', $passportPath, '-TargetState', 'active', '-EvidenceRef', 'sha256:release', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-ApproverId', 'owner_1', '-PassThru')
$cases.Add([pscustomobject]@{ name = 'approved_tool_can_be_activated'; passed = ($sandbox.code -eq 0 -and $approved.code -eq 0 -and $active.code -eq 0 -and $active.text -match 'permission_expanded.*false') })
$allowed = RunJson $gate @('-PassportPath', $passportPath, '-Environment', 'internal', '-Operation', 'read', '-TenantId', 'tenant_1', '-OrganizationId', 'org_1', '-ProjectId', 'project_1', '-RoleId', 'finance', '-DataScopeRef', 'scope://amounts_and_refunds', '-PolicyRef', 'policy://order-read', '-DecisionReason', 'approved finance read', '-ResponsibleParty', 'owner_1', '-AgentId', 'agent_1', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-EstimatedCost', '1', '-CallsUsed', '0', '-CallLimit', '10', '-BudgetUsed', '0', '-BudgetLimit', '10', '-PassThru')
$cases.Add([pscustomobject]@{ name = 'released_tool_still_requires_task_grant'; passed = ($allowed.code -eq 0 -and $allowed.text -match 'requires_task_grant.*true') })
$overBudget = RunJson $gate @('-PassportPath', $passportPath, '-Environment', 'internal', '-Operation', 'read', '-TenantId', 'tenant_1', '-OrganizationId', 'org_1', '-ProjectId', 'project_1', '-RoleId', 'finance', '-DataScopeRef', 'scope://amounts_and_refunds', '-PolicyRef', 'policy://order-read', '-DecisionReason', 'approved finance read', '-ResponsibleParty', 'owner_1', '-AgentId', 'agent_1', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-EstimatedCost', '2', '-CallsUsed', '0', '-CallLimit', '10', '-BudgetUsed', '9', '-BudgetLimit', '10', '-PassThru')
$cases.Add([pscustomobject]@{ name = 'budget_overrun_is_blocked'; passed = (Has $overBudget 'task_budget_exceeded') })
$feedbackRun = RunJson $feedback @('-PassportPath', $passportPath, '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-FeedbackType', 'unnecessary_call', '-EvidenceRef', 'sha256:feedback', '-ProposedChange', 'cache duplicate lookup', '-PassThru')
$cases.Add([pscustomobject]@{ name = 'feedback_creates_candidate_without_authority'; passed = ($feedbackRun.code -eq 0 -and $feedbackRun.text -match 'permission_expanded.*false' -and $feedbackRun.text -match 'auto_published.*false') })
$trialRun = RunJson $trial @('-PassportPath', $passportPath, '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-TestPlanRef', 'sha256:test-plan', '-SandboxRef', 'sandbox://isolated-1', '-EvidenceRef', 'sha256:trial-evidence', '-Result', 'passed', '-PassThru')
$trialPath = if ($trialRun.code -eq 0) { ($trialRun.text | ConvertFrom-Json).trial_path } else { '' }
$cases.Add([pscustomobject]@{ name = 'trial_isolated_from_production'; passed = ($trialRun.code -eq 0 -and $trialRun.text -match 'production_authority.*false' -and $trialRun.text -match 'external_calls.*false') })
$verifyRun = RunJson $verify @('-TrialReceiptPath', $trialPath, '-VerifierId', 'verifier_1', '-VerificationEvidenceRef', 'sha256:verification-evidence', '-Result', 'passed', '-PassThru')
$cases.Add([pscustomobject]@{ name = 'trial_requires_independent_verification'; passed = ($verifyRun.code -eq 0 -and $verifyRun.text -match 'production_authority.*false') })
$trustRun = RunJson $trust @('-PassportPath', $passportPath, '-QualityScore', '0.9', '-SecurityScore', '0.8', '-EvidenceScore', '0.9', '-ReliabilityScore', '0.8', '-EvidenceRef', 'sha256:trust-evidence', '-PassThru')
$cases.Add([pscustomobject]@{ name = 'trust_score_does_not_expand_permission'; passed = ($trustRun.code -eq 0 -and $trustRun.text -match 'trust_score' -and $trustRun.text -match 'permission_expanded.*false') })
$previousPath = Join-Path $root ('.qianlima/run-traces/enterprise-tools/registry/test-previous-' + $suffix + '.json')
$previous = RunJson $register @('-ToolId', 'test_read_tool', '-ToolVersion', '0.9.0', '-OwnerId', 'owner_1', '-TenantId', 'tenant_1', '-OrganizationId', 'org_1', '-ProjectId', 'project_1', '-Purpose', 'previous read-only test tool', '-ApplicableScenarios', 'finance lookup', '-InputSchemaRef', 'sha256:input', '-OutputSchemaRef', 'sha256:output', '-CapabilityBoundary', 'read:internal_sanitized', '-AccessPermissions', 'read:assigned_scope', '-DataClass', 'internal_sanitized', '-DeclaredDependencies', 'runtime://approved', '-RiskLevel', 'L2', '-CostModel', 'fixed:1', '-AuditRequirements', 'policy_reason;verification_ref', '-RollbackRef', 'sha256:rollback', '-ArtifactRef', 'sha256:previous-artifact', '-IntegrityHash', $hash, '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-OutputPath', $previousPath, '-PassThru')
$previousStatic = RunJson $state @('-PassportPath', $previousPath, '-TargetState', 'static_checked', '-EvidenceRef', 'sha256:previous-static', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-ApproverId', 'owner_1', '-PassThru')
$previousSandbox = RunJson $state @('-PassportPath', $previousPath, '-TargetState', 'sandboxed', '-EvidenceRef', 'sha256:previous-sandbox', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-ApproverId', 'owner_1', '-PassThru')
$previousApproved = RunJson $state @('-PassportPath', $previousPath, '-TargetState', 'approved', '-EvidenceRef', 'sha256:previous-approval', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-ApproverId', 'owner_1', '-PassThru')
$rollbackRun = RunJson $rollback @('-CurrentPassportPath', $passportPath, '-PreviousPassportPath', $previousPath, '-Reason', 'verified regression', '-TaskId', 'task_tool_1', '-GrantId', 'grant_tool_1', '-TraceId', 'trace_tool_1', '-ApproverId', 'owner_1', '-PassThru')
$cases.Add([pscustomobject]@{ name = 'version_rollback_is_explicit_and_non_escalating'; passed = ($previous.code -eq 0 -and $previousStatic.code -eq 0 -and $previousSandbox.code -eq 0 -and $previousApproved.code -eq 0 -and $rollbackRun.code -eq 0 -and $rollbackRun.text -match 'production_authority.*false') })
$failed = @($cases | Where-Object { -not $_.passed })
$out = [pscustomobject]@{ passed = ($failed.Count -eq 0); cases = @($cases); permission_expanded = $false; auto_published = $false; external_calls = $false; production_writes = $false }
if ($PassThru) { $out | ConvertTo-Json -Depth 12 } else { $cases | Format-Table -AutoSize }
if ($failed.Count) { throw ('Enterprise tool governance regression failed: ' + (($failed.name) -join ', ')) }
