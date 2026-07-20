<#
.SYNOPSIS
  Verify a task-bound Sandbox Attestation without starting a Runner.
.DESCRIPTION
  Pure validation helper. It checks registry, Work Order, Grant, isolation
  path, expiry, policy fields, and status. Pending candidates are rejected.
#>
param(
  [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9._:-]{3,100}$')] [string]$RunnerId,
  [Parameter(Mandatory)] [string]$WorkOrderPath,
  [Parameter(Mandatory)] [string]$GrantPath,
  [Parameter(Mandatory)] [string]$AttestationPath,
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$traceRoot = Join-Path $projectRoot '.qianlima\run-traces'
$registry = Get-Content -LiteralPath (Join-Path $projectRoot '.qianlima\execution-runners.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$runner = @($registry.runners | Where-Object { $_.runner_id -eq $RunnerId }) | Select-Object -First 1
if ($null -eq $runner) { throw "Unknown Runner: $RunnerId" }

function Read-GovernedJson([string]$Path, [string]$Root, [string]$Label) {
  $full = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw "$Label is outside its governed root." }
  return Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json
}
$order = Read-GovernedJson $WorkOrderPath (Join-Path $traceRoot 'work-orders') 'Work Order'
$grant = Read-GovernedJson $GrantPath (Join-Path $traceRoot 'delegation-grants') 'Grant'
$attestation = Read-GovernedJson $AttestationPath (Join-Path $traceRoot 'sandbox-attestations') 'Attestation'

$failures = @()
function Fail([string]$Reason) { $script:failures += $Reason }
if ($runner.requires_attestation -ne $true) { Fail 'runner_does_not_require_attestation' }
if ($runner.enabled -ne $true -or $runner.execution_enabled -ne $true) { Fail 'runner_execution_disabled' }
if ($grant.status -ne 'issued') { Fail 'grant_not_issued' }
if ($grant.task_id -ne $order.task_id -and $grant.task_id -ne $order.work_order_id) { Fail 'grant_order_binding_mismatch' }
if ($order.agent_id -ne $grant.agent_id) { Fail 'grant_agent_binding_mismatch' }
if (@($runner.supported_agents) -notcontains $grant.agent_id) { Fail 'runner_agent_unsupported' }
if ($attestation.status -ne 'verified') { Fail 'attestation_not_verified' }
if ($attestation.runner_id -ne $RunnerId) { Fail 'attestation_runner_mismatch' }
if ($attestation.task_id -ne $grant.task_id) { Fail 'attestation_task_mismatch' }
if ($attestation.agent_id -ne $grant.agent_id) { Fail 'attestation_agent_mismatch' }
if ($attestation.grant_id -ne $grant.grant_id) { Fail 'attestation_grant_mismatch' }
if ($attestation.host_workspace_mounted -ne $false) { Fail 'host_workspace_mounted' }
if ($attestation.agent_network -ne 'none') { Fail 'network_not_none' }
if ($attestation.mcp_mode -ne 'allowlist_read_only') { Fail 'mcp_not_read_only_allowlist' }
if ($attestation.file_export -ne $false) { Fail 'file_export_enabled' }
if ($attestation.web_access -ne $false) { Fail 'web_access_enabled' }
if ($attestation.erp_access -ne $false) { Fail 'erp_access_enabled' }
if ($attestation.secret_mode -ne 'secret_ref_only') { Fail 'secret_mode_invalid' }
if ([datetime]$grant.expires_at -le (Get-Date).ToUniversalTime()) { Fail 'grant_expired' }
if ([datetime]$attestation.expires_at -le (Get-Date).ToUniversalTime()) { Fail 'attestation_expired' }
if ([datetime]$attestation.expires_at -gt [datetime]$grant.expires_at) { Fail 'attestation_outlives_grant' }
if ([string]$attestation.evidence_hash -notmatch '^sha256:[0-9a-fA-F]{64}$') { Fail 'evidence_hash_invalid' }
$taskRoot = [IO.Path]::GetFullPath((Join-Path $traceRoot "sandbox-workspaces/$($grant.task_id)")).TrimEnd('\','/')
$iso = [IO.Path]::GetFullPath([string]$attestation.isolation_root)
if (-not ($iso -eq $taskRoot -or $iso.StartsWith($taskRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) { Fail 'isolation_root_outside_task' }
if (-not (Test-Path -LiteralPath $iso -PathType Container)) { Fail 'isolation_root_missing' }

$result = [ordered]@{ schema_version=1; runner_id=$RunnerId; task_id=$grant.task_id; grant_id=$grant.grant_id; attestation_id=$attestation.attestation_id; verified=($failures.Count -eq 0); failures=@($failures); process_started=$false; network_called=$false; external_write=$false }
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { Write-Host "Sandbox Attestation verified=$($result.verified)"; $failures | ForEach-Object { Write-Host "  FAILED $_" } }
if ($failures.Count -gt 0) { exit 20 }
