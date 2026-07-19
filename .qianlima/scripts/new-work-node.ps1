<#
.SYNOPSIS
  Create a Work Node (work-node-contract.json) binding an R&D milestone to an
  owner, a scope, and acceptance criteria. Broker-owned; agents cannot call this.
#>
param(
  [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')] [string]$WorkNodeId,
  [Parameter(Mandatory)] [string]$GoalId,
  [Parameter(Mandatory)] [ValidateLength(1,120)] [string]$Milestone,
  [Parameter(Mandatory)] [string]$Owner,
  [Parameter(Mandatory)] [string]$RepoRoot,
  [string[]]$AllowedPaths = @(),
  [string[]]$ExcludedPaths = @(),
  [bool]$TestsRequired = $true,
  [string]$TestResultRef = '',
  [int]$MinActionReceipts = 1,
  [ValidateSet('L0','L1','L2','L3','L4')] [string]$RiskCeiling = 'L2',
  [ValidateSet('rule_check','test_gate','independent_checker')] [string]$VerifierType = 'test_gate',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$nodeDir = Join-Path $root 'run-traces/work-nodes'
if (-not (Test-Path -LiteralPath $nodeDir -PathType Container)) { New-Item -ItemType Directory -Path $nodeDir -Force | Out-Null }
$nodePath = Join-Path $nodeDir "$WorkNodeId.json"
if (Test-Path -LiteralPath $nodePath) { Write-Error "Work Node already exists (immutable core): $WorkNodeId"; exit 12 }

# policy_hash: hash the active protected-invariants file for traceability
$policyFile = Join-Path $root 'protected-invariants.yaml'
$policyHash = 'sha256:0000000000000000000000000000000000000000000000000000000000000000'
if (Test-Path -LiteralPath $policyFile) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $policyHash = 'sha256:' + ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($policyFile))) -replace '-','').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

$node = [ordered]@{
  schema_version = 1
  node_type      = 'qianlima_work_node'
  work_node_id   = $WorkNodeId
  goal_id        = $GoalId
  milestone      = $Milestone
  owner          = $Owner
  scope          = [ordered]@{ repo_root = $RepoRoot; allowed_paths = $AllowedPaths; excluded_paths = $ExcludedPaths }
  acceptance_criteria = [ordered]@{
    tests_required = $TestsRequired; test_result_ref = $TestResultRef
    diff_subset_of_scope = $true; policy_hash = $policyHash; min_action_receipts = $MinActionReceipts
  }
  fff_binding    = 'fff-capability-spec.yaml'
  verification   = [ordered]@{ verifier_type = $VerifierType; required_receipts = @('action_receipt','artifact_receipt') }
  risk_ceiling   = $RiskCeiling
  status         = 'draft'
  grant_id       = $null
  verified_at    = $null
  created_at     = (Get-Date).ToUniversalTime().ToString('o')
}
[IO.File]::WriteAllText($nodePath, ($node | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Host "Work Node created: $nodePath (status=draft, policy=$($policyHash.Substring(0,20))...)"
if ($PassThru) { [PSCustomObject]$node }
