<#
.SYNOPSIS
  Read-only contract regression for the R&D P0 governance loop.
#>
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Require([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}
function Read-Json([string]$Path) {
  return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Read-Source([string]$RelativePath) {
  return Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Raw -Encoding UTF8
}

$actionContract = Read-Json (Join-Path $projectRoot '.qianlima\specifications\action-receipt-contract.json')
$nodeContract = Read-Json (Join-Path $projectRoot '.qianlima\specifications\work-node-contract.json')
$projectionContract = Read-Json (Join-Path $projectRoot '.qianlima\specifications\manager-projection-contract.json')
$runtimeContract = Read-Json (Join-Path $projectRoot '.qianlima\specifications\runtime-adapter-contract.json')
$subagentContract = Read-Json (Join-Path $projectRoot '.qianlima\specifications\typed-subagent-result-contract.json')
$artifactContract = Read-Json (Join-Path $projectRoot '.qianlima\specifications\artifact-precondition-contract.json')
$nestedContract = Read-Json (Join-Path $projectRoot '.qianlima\specifications\nested-capability-receipt-contract.json')
$attestationContract = Read-Json (Join-Path $projectRoot '.qianlima\specifications\sandbox-attestation-contract.json')
$piAdmissionSource = Read-Source '.qianlima\scripts\test-pi-shadow-admission.ps1'
$attestationTestSource = Read-Source '.qianlima\scripts\test-sandbox-attestation-contract.ps1'
$enterpriseGoalContract = @(Get-ChildItem -LiteralPath $projectRoot -Directory | ForEach-Object {
  $candidate = Join-Path $_.FullName 'goal-work-graph-contract.json'
  if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidate }
})
Require ($enterpriseGoalContract.Count -eq 1) 'Expected exactly one Enterprise goal-work-graph contract.'
$goalContract = Read-Json $enterpriseGoalContract[0]

Require (@($actionContract.required) -contains 'sequence') 'P0 Action Receipt must require a sequence.'
Require ((@($actionContract.invariants) -match 'sequence must be contiguous').Count -gt 0) 'P0 Action Receipt must require a contiguous chain.'
Require (@($nodeContract.lifecycle) -contains 'verified') 'P0 Work Node lifecycle must contain verified.'
Require ((@($nodeContract.invariants) -match 'Agent can never write status=verified').Count -gt 0) 'P0 must forbid Agent self-verification.'
Require ((@($projectionContract.generated_from_only) -match 'never Agent self-report').Count -gt 0) 'Manager projection must exclude Agent self-report.'
Require (@($projectionContract.required) -contains 'evidence_refs') 'Manager projection must expose traceable evidence refs.'
Require (@($goalContract.manager_projection.prohibited_fields) -contains 'unverified_completion_claim') 'Enterprise manager projection must prohibit unverified completion claims.'
Require (@($goalContract.work_node.state_values) -contains 'verified') 'Enterprise goal graph must use verified, not Agent-completed, state.'
Require ($runtimeContract.status -eq 'discover_only') 'New runtimes must remain discover-only until Broker admission.'
Require (@($runtimeContract.launch_modes) -contains 'rpc') 'Runtime Adapter must support a structured RPC boundary.'
Require (@($runtimeContract.capabilities.broker_only) -contains 'verify') 'Runtime Adapter must not own verification.'
Require (@($subagentContract.required) -contains 'schema_ref') 'Subagent results must carry a versioned schema reference.'
Require ((@($subagentContract.invariants) -match 'not verification evidence').Count -gt 0) 'Subagent output must not become verification by itself.'
Require (@($artifactContract.precondition_checks) -contains 'base_hash_matches') 'Artifact writes must check the base hash.'
Require ((@($artifactContract.invariants) -match 'stale artifact').Count -gt 0) 'Stale artifacts must be rejected.'
Require ((@($nestedContract.invariants) -match 'preserve trace_id').Count -gt 0) 'Nested callbacks must preserve the parent trace.'
Require (@($attestationContract.verified_required_fields) -contains 'grant_id') 'Attestation must be Grant-bound.'
Require ((@($attestationContract.invariants) -match 'pending candidate').Count -gt 0) 'Pending Attestation candidates must not be executable.'
Require ($piAdmissionSource -match 'eligible_for_shadow_execution') 'Pi admission must expose an explicit shadow eligibility result.'
Require ($piAdmissionSource -match 'no_task_bound_runner_registration') 'Pi admission must block when no Runner is registered.'
Require ($piAdmissionSource -match 'vendor_process_started = \$false') 'Pi admission must prove it starts no vendor process.'
Require ($attestationTestSource -match 'Unknown Runner rejection path') 'Attestation rejection regression must cover unknown Runner.'

$actionSource = Read-Source '.qianlima\scripts\new-action-receipt.ps1'
$fffSource = Read-Source '.qianlima\scripts\invoke-fff-scoped.ps1'
$verifySource = Read-Source '.qianlima\scripts\verify-work-node.ps1'
$bindSource = Read-Source '.qianlima\scripts\bind-work-node-grant.ps1'
$projectionSource = Read-Source '.qianlima\scripts\new-manager-projection.ps1'
$adapterSource = Read-Source '.qianlima\agent-runtime-adapters.yaml'

Require ($actionSource -match 'next contiguous value') 'Action Receipt writer must reject sequence gaps.'
Require ($fffSource -match 'grant\.expires_at') 'fff gateway must reject expired Grants.'
Require ($fffSource -match "allowed_tools\) -notcontains 'fff'") 'fff gateway must require the fff capability in the Grant.'
Require ($verifySource -match "EventType 'verification_completed'") 'Verifier must emit the canonical verification event.'
Require ($verifySource -match 'receipt_sequence_gap_or_duplicate') 'Verifier must independently check receipt continuity.'
Require ($bindSource -match "status = 'granted'") 'Broker binding must move the node to granted.'
Require ($projectionSource -match 'acceptedVerification') 'Manager projection must require accepted verification evidence.'
Require ($projectionSource -match "EventType 'manager_projection_published'") 'Manager projection must emit an audit event.'
Require ($actionSource -match '\$TraceId') 'Action Receipt writer must emit a trace id.'
Require ($adapterSource -match 'id: pi_worker') 'Pi must be registered as a discover-only adapter.'
Require ($adapterSource -match 'id: oh_my_pi_worker') 'oh-my-pi must be registered as a discover-only adapter.'

$scripts = @(
  '.qianlima\scripts\new-action-receipt.ps1',
  '.qianlima\scripts\invoke-fff-scoped.ps1',
  '.qianlima\scripts\verify-work-node.ps1',
  '.qianlima\scripts\bind-work-node-grant.ps1',
  '.qianlima\scripts\new-manager-projection.ps1'
  ,'.qianlima\scripts\test-pi-shadow-admission.ps1'
  ,'.qianlima\scripts\test-sandbox-attestation-contract.ps1'
)
foreach ($script in $scripts) {
  $tokens = $null; $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot $script), [ref]$tokens, [ref]$errors)
  Require ($errors.Count -eq 0) "PowerShell parser rejected $script"
}

Write-Host 'R&D P0 governance contract regression passed.'
