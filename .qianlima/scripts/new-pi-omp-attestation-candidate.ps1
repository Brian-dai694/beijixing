<#
.SYNOPSIS
  Create a pending Pi/oh-my-pi Sandbox Attestation candidate.
.DESCRIPTION
  This script never probes or starts pi, omp, Docker, MCP, or a provider. The
  candidate documents the exact bindings a future Runner must prove. It is
  intentionally status=pending and cannot pass invoke-governed-runner.ps1.
#>
param(
  [Parameter(Mandatory)] [ValidateSet('pi_worker','oh_my_pi_worker')] [string]$AgentId,
  [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9._-]{3,100}$')] [string]$TaskId,
  [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9._-]{3,100}$')] [string]$GrantId,
  [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9._-]{3,100}$')] [string]$RunnerId,
  [Parameter(Mandatory)] [string]$IsolationRoot,
  [ValidateRange(1,30)] [int]$ExpiresMinutes = 10,
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$traceRoot = Join-Path $projectRoot '.qianlima\run-traces'
$attestationRoot = [IO.Path]::GetFullPath((Join-Path $traceRoot 'sandbox-attestations')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
$grantPath = Join-Path $traceRoot "delegation-grants/$GrantId.json"
if (-not (Test-Path -LiteralPath $grantPath -PathType Leaf)) { throw "Grant not found: $GrantId" }
$grant = Get-Content -LiteralPath $grantPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($grant.task_id -ne $TaskId) { throw 'Grant task_id must match TaskId.' }
if ($grant.agent_id -ne $AgentId) { throw 'Grant agent_id must match AgentId.' }
if ([datetime]$grant.expires_at -le (Get-Date).ToUniversalTime()) { throw 'Grant is expired.' }
$registry = Get-Content -LiteralPath (Join-Path $projectRoot '.qianlima\execution-runners.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$runner = @($registry.runners | Where-Object { $_.runner_id -eq $RunnerId }) | Select-Object -First 1
if ($null -eq $runner) { throw "Runner not found: $RunnerId" }
if (@($runner.supported_agents) -notcontains $AgentId) { throw "Runner does not support Agent: $AgentId" }
if ($runner.enabled -ne $false -or $runner.execution_enabled -ne $false) { throw 'Candidate generator only accepts a disabled contract-only Runner.' }
if ($runner.requires_attestation -ne $true) { throw 'Runner must require a verified Attestation.' }

$taskRoot = [IO.Path]::GetFullPath((Join-Path $traceRoot "sandbox-workspaces/$TaskId")).TrimEnd('\','/')
$isolationFull = [IO.Path]::GetFullPath($IsolationRoot)
if (-not ($isolationFull.StartsWith($taskRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $isolationFull -eq $taskRoot)) { throw 'IsolationRoot must be inside the task-specific sandbox workspace.' }
if (-not (Test-Path -LiteralPath $isolationFull -PathType Container)) { throw 'IsolationRoot does not exist.' }

$expiresAt = (Get-Date).ToUniversalTime().AddMinutes($ExpiresMinutes)
if ($expiresAt -gt [datetime]$grant.expires_at) { $expiresAt = [datetime]$grant.expires_at }
$candidateId = "sandbox-candidate-$AgentId-$TaskId-$([Guid]::NewGuid().ToString('n').Substring(0,12))"
$metadata = [ordered]@{ agent_id=$AgentId; task_id=$TaskId; grant_id=$GrantId; runner_id=$RunnerId; isolation_root=$isolationFull; created_at=(Get-Date).ToUniversalTime().ToString('o') }
$sha = [Security.Cryptography.SHA256]::Create()
try { $evidenceHash = 'sha256:' + (([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($metadata | ConvertTo-Json -Compress)))) -replace '-','').ToLowerInvariant()) }
finally { $sha.Dispose() }

$candidate = [ordered]@{
  schema_version=1; contract_type='qianlima_sandbox_attestation'; attestation_type='candidate'; attestation_id=$candidateId
  runner_id=$RunnerId; provider='contract_only'; agent_id=$AgentId; task_id=$TaskId; grant_id=$GrantId; status='pending'
  sandbox_type='unverified'; isolation_root=$isolationFull; host_workspace_mounted=$null; agent_network='unknown'; mcp_mode='unknown'; mcp_servers=@()
  file_export=$null; web_access=$null; erp_access=$null; secret_mode='unknown'; policy_hash=$null; expires_at=$expiresAt.ToString('o'); evidence_hash=$evidenceHash
  issued_at=(Get-Date).ToUniversalTime().ToString('o'); issuer_ref='pending_runner_attestation'; note='Candidate only. No process, probe, network, MCP, or Docker call was made.'
}
$outPath = Join-Path $attestationRoot "$candidateId.json"
if (-not (Test-Path -LiteralPath (Split-Path -Parent $outPath) -PathType Container)) { New-Item -ItemType Directory -Path (Split-Path -Parent $outPath) -Force | Out-Null }
[IO.File]::WriteAllText($outPath, ($candidate | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
if ($PassThru) { $candidate | ConvertTo-Json -Depth 10 } else { Write-Host "Pending Sandbox Attestation candidate written: $outPath" }
