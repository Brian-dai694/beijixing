<#
.SYNOPSIS
  Read-only admission preflight for Pi and oh-my-pi shadow execution.
.DESCRIPTION
  This script never starts pi, omp, Docker, MCP, a model provider, or a
  vendor process. It only evaluates whether the current contracts are strong
  enough to permit a future shadow run. Discover-only adapters are expected to
  remain blocked until a task-bound Runner registration and attestation exist.
#>
param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Require([bool]$Condition, [string]$Name, [string]$Reason) {
  if (-not $Condition) { $script:failures += [ordered]@{ check=$Name; reason=$Reason } }
}
function Read-Json([string]$RelativePath) {
  return Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Read-Text([string]$RelativePath) {
  return Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Raw -Encoding UTF8
}

$failures = @()
$adaptersText = Read-Text '.qianlima\agent-runtime-adapters.yaml'
$policyText = Read-Text '.qianlima\agent-runtime-policy.yaml'
$protocolText = Read-Text '.qianlima\specifications\north-star-protocol.json'
$shadowText = Read-Text '.qianlima\shadow-run-policy.yaml'
$runtime = Read-Json '.qianlima\specifications\runtime-adapter-contract.json'
$attestationContract = Read-Json '.qianlima\specifications\sandbox-attestation-contract.json'
$runner = Read-Json '.qianlima\execution-runners.json'
$agentCardsText = Read-Text '.qianlima\agent-cards.yaml'

Require ($adaptersText -match '(?ms)^default_mode:\s*dry_run') 'adapter_default_dry_run' 'Runtime adapter registry must default to dry_run.'
Require ($adaptersText -match '(?ms)^network_dispatch:\s*deny') 'adapter_network_denied' 'Runtime adapter registry must deny network dispatch.'
Require ($adaptersText -match '(?ms)^direct_agent_to_agent:\s*deny') 'adapter_a2a_denied' 'Direct Agent-to-Agent communication must remain denied.'
Require ($adaptersText -match '(?ms)^\s*- id: pi_worker\b[\s\S]*?availability:\s*discover_only[\s\S]*?default_mode:\s*dry_run') 'pi_discover_only' 'Pi must remain discover-only and dry-run.'
Require ($adaptersText -match '(?ms)^\s*- id: oh_my_pi_worker\b[\s\S]*?availability:\s*discover_only[\s\S]*?default_mode:\s*dry_run') 'omp_discover_only' 'oh-my-pi must remain discover-only and dry-run.'
Require ($policyText -match '(?ms)host_direct_execution:\s*deny') 'host_execution_denied' 'Host direct execution must remain denied.'
Require ($adaptersText -match '(?ms)dry_run_is_not_execution:\s*true') 'dry_run_not_execution' 'Dry-run must not be treated as execution.'
Require ($protocolText -match 'Unknown, expired, revoked, over-budget, drifted, or unverified work is denied or frozen') 'policy_fail_closed' 'Runtime policy must fail closed on unknown or drifted work.'
Require ($shadowText -match '(?ms)write_enabled:\s*false') 'shadow_writes_disabled' 'Shadow mode must not write business state.'
Require ($shadowText -match '(?ms)external_write|forbidden_actions') 'shadow_forbidden_actions' 'Shadow policy must declare forbidden actions.'
Require ($runtime.status -eq 'discover_only') 'runtime_contract_discover_only' 'Runtime contract must remain discover-only before admission.'
Require ($runtime.isolation.required -eq $true) 'runtime_isolation_required' 'Runtime adapter requires an isolated Runner.'
Require (@($attestationContract.verified_required_fields) -contains 'grant_id') 'attestation_grant_binding' 'Attestation must bind to a Grant.'
Require (@($attestationContract.verified_required_fields) -contains 'policy_hash') 'attestation_policy_binding' 'Attestation must carry the policy hash.'
Require ($agentCardsText -match '(?ms)^\s*- id: pi_worker\b[\s\S]*?availability:\s*discover_only') 'pi_agent_card' 'Pi must have a discover-only Agent Card.'
Require ($agentCardsText -match '(?ms)^\s*- id: oh_my_pi_worker\b[\s\S]*?availability:\s*discover_only') 'omp_agent_card' 'oh-my-pi must have a discover-only Agent Card.'
Require (@($runtime.capabilities.broker_only) -contains 'verify') 'runtime_verification_broker_only' 'Runtime cannot own verification.'
Require (@($runtime.capabilities.broker_only) -contains 'adopt') 'runtime_adoption_broker_only' 'Runtime cannot own adoption.'
Require ($runner.default_action -eq 'deny') 'runner_default_deny' 'Runner default action must be deny.'
Require ($runner.host_direct_execution -eq 'deny') 'runner_host_direct_denied' 'Runner must deny host direct execution.'
Require ($runner.execution_enabled_by_default -eq $false) 'runner_execution_disabled' 'Runner execution must remain disabled by default.'

$registeredPiRunners = @($runner.runners | Where-Object { @($_.supported_agents) -contains 'pi_worker' -or @($_.supported_agents) -contains 'oh_my_pi_worker' })
foreach ($piRunner in $registeredPiRunners) {
  Require ($piRunner.enabled -eq $false) "runner_disabled_$($piRunner.runner_id)" 'Pi/oh-my-pi Runner registration must remain disabled.'
  Require ($piRunner.execution_enabled -eq $false) "runner_execution_disabled_$($piRunner.runner_id)" 'Pi/oh-my-pi Runner execution must remain disabled.'
  Require ($piRunner.network_policy -eq 'none') "runner_network_denied_$($piRunner.runner_id)" 'Pi/oh-my-pi Runner network must remain disabled.'
  Require ($piRunner.file_export -eq $false) "runner_export_denied_$($piRunner.runner_id)" 'Pi/oh-my-pi Runner file export must remain disabled.'
  Require ($piRunner.isolation.host_workspace_mounted -eq $false) "runner_host_mount_denied_$($piRunner.runner_id)" 'Pi/oh-my-pi Runner may not mount the host workspace.'
  Require ($piRunner.requires_attestation -eq $true) "runner_attestation_required_$($piRunner.runner_id)" 'Pi/oh-my-pi Runner requires a verified task-bound attestation.'
}
if ($registeredPiRunners.Count -eq 0) {
  $script:blockedReason = 'no_task_bound_runner_registration'
  $script:nextGate = 'Register a disabled-by-default Runner contract for pi/omp, then issue a task-bound sandbox attestation.'
} else {
  $script:blockedReason = 'runner_registration_requires_attestation'
  $script:nextGate = 'Verify the Runner attestation, then run a synthetic shadow task with no vendor process side effect.'
}

$result = [ordered]@{
  schema_version = 1
  check_type = 'qianlima_pi_shadow_admission'
  pi_adapter = 'pi_worker'
  oh_my_pi_adapter = 'oh_my_pi_worker'
  eligible_for_shadow_execution = ($failures.Count -eq 0 -and $registeredPiRunners.Count -gt 0)
  status = if ($failures.Count -gt 0) { 'rejected' } elseif ($registeredPiRunners.Count -eq 0) { 'blocked' } else { 'pending_attestation' }
  blocked_reason = if ($failures.Count -gt 0) { 'contract_boundary_failed' } else { $blockedReason }
  next_gate = if ($failures.Count -gt 0) { 'Fix the failed contract checks before any Runtime admission.' } else { $nextGate }
  failed_checks = @($failures)
  registered_runner_count = $registeredPiRunners.Count
  vendor_process_started = $false
  docker_started = $false
  network_called = $false
  external_write = $false
}

if ($PassThru) { [PSCustomObject]$result | ConvertTo-Json -Depth 10 }
else {
  Write-Host "Pi shadow admission: $($result.status)"
  Write-Host "  eligible_for_shadow_execution=$($result.eligible_for_shadow_execution)"
  Write-Host "  blocked_reason=$($result.blocked_reason)"
  Write-Host "  next_gate=$($result.next_gate)"
  if ($failures.Count -gt 0) { $failures | ForEach-Object { Write-Host "  FAILED [$($_.check)] $($_.reason)" } }
}
if ($failures.Count -gt 0) { exit 20 }
