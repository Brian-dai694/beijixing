param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$contractPath = Join-Path $root 'capability-execution-classification.yaml'
$skillPath = Join-Path $root 'skill-registry.yaml'
$workflowPath = Join-Path $root 'workflow-index.yaml'
$validator = Join-Path $PSScriptRoot 'validate-capability-execution-class.ps1'
$contract = Get-Content $contractPath -Raw -Encoding UTF8
$skillText = Get-Content $skillPath -Raw -Encoding UTF8
$workflowText = Get-Content $workflowPath -Raw -Encoding UTF8
$cases = [System.Collections.Generic.List[object]]::new()
function Add-Case($Name, $Passed) { $cases.Add([PSCustomObject]@{name=$Name;passed=[bool]$Passed}) }

$registeredSkills = @([regex]::Matches($skillText, '(?m)^\s{4}- skill_id:\s*([^\s#]+)') | ForEach-Object {$_.Groups[1].Value})
$registeredWorkflows = @([regex]::Matches($workflowText, '(?m)^\s{2}- id:\s*([^\s#]+)') | ForEach-Object {$_.Groups[1].Value})
foreach ($id in $registeredSkills) { Add-Case ("skill_classified_" + $id) ($contract -match "(?m)^\s{6}- $([regex]::Escape($id))\s*$") }
foreach ($id in $registeredWorkflows) { Add-Case ("workflow_classified_" + $id) ($contract -match "(?m)^\s{6}- $([regex]::Escape($id))\s*$") }

$tool = & $validator -Class deterministic_tool -PassThru | ConvertFrom-Json
Add-Case 'deterministic_tool_allowed' $tool.allowed
$knowledge = & $validator -Class on_demand_knowledge -HasMinimumEvidencePack $true -PassThru | ConvertFrom-Json
Add-Case 'knowledge_pack_allowed' $knowledge.allowed
$delegation = & $validator -Class independent_delegation -HasIndependentGoal $true -HasChildWorkOrder $true -HasChildGrant $true -PassThru | ConvertFrom-Json
Add-Case 'isolated_delegation_allowed' $delegation.allowed
$deniedOutput = & $validator -Class independent_delegation -HasIndependentGoal $true -HasChildWorkOrder $true -HasChildGrant $true -InheritsParentPermissions $true -PassThru
$deniedCode = $LASTEXITCODE
$denied = $deniedOutput | ConvertFrom-Json
Add-Case 'parent_permission_inheritance_denied' (-not $denied.allowed -and $deniedCode -eq 2)
$approvalOutput = & $validator -Class deterministic_tool -RequestsWriteExternalSendOrBudgetChange $true -PassThru
$approvalCode = $LASTEXITCODE
$approval = $approvalOutput | ConvertFrom-Json
Add-Case 'new_approval_required_for_authority_change' (-not $approval.allowed -and $approvalCode -eq 2)
Add-Case 'runtime_shortcuts_preserved' ($contract.Contains('ordinary_chat: no_runtime') -and $contract.Contains('same_goal_follow_up: inherit_conversation_without_runtime'))
Add-Case 'memory_and_improvement_governed' ($contract.Contains('every_change_requires_replay_before_promotion: true') -and $contract.Contains('silent_memory_overwrite: deny'))

$failed = @($cases | Where-Object {-not $_.passed})
$result = [PSCustomObject]@{passed=($failed.Count -eq 0);cases=@($cases);external_calls=$false;permissions_granted=$false}
if ($PassThru) {$result|ConvertTo-Json -Depth 6} else {$cases|Format-Table -AutoSize}
if ($failed.Count) { throw ('Capability execution class regression failed: ' + ($failed.name -join ', ')) }
