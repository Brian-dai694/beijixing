param(
  [Parameter(Mandatory = $true)] [string]$AgentId,
  [Parameter(Mandatory = $true)] [string]$EnvelopePath,
  [string]$RegistryPath = '',
  [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot '.qianlima\a2a-remote-registry.json' }
$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$envelope = Get-Content -LiteralPath $EnvelopePath -Raw -Encoding UTF8 | ConvertFrom-Json

function Deny([string]$Reason) {
  throw "A2A dispatch denied: $Reason"
}

if ($registry.default_action -ne 'deny') { Deny 'Registry default action must remain deny.' }
if ($registry.network_dispatch_enabled -ne $false) { Deny 'Network dispatch is disabled until a separate explicit approval.' }
$agent = @($registry.agents | Where-Object { $_.id -eq $AgentId }) | Select-Object -First 1
if (-not $agent) { Deny 'Agent is not allowlisted.' }
if (-not $agent.enabled) { Deny 'Allowlisted agent is disabled.' }
if ($envelope.protocol_target -notlike 'A2A 1.0*') { Deny 'Envelope protocol version is not supported.' }
# Compare risk by numeric rank, not string order, so the ceiling check is robust and consistent with qianlima-context-fast.ps1.
$riskRank = @{ L0 = 0; L1 = 1; L2 = 2; L3 = 3; L4 = 4 }
$envelopeRisk = $envelope.delegation.risk_ceiling
$agentRisk = $agent.risk_ceiling
if (-not $riskRank.ContainsKey([string]$envelopeRisk)) { Deny "Envelope risk ceiling is unknown: $envelopeRisk" }
if (-not $riskRank.ContainsKey([string]$agentRisk)) { Deny "Agent risk ceiling is unknown: $agentRisk" }
if ($envelopeRisk -eq 'L4' -or $riskRank[[string]$envelopeRisk] -gt $riskRank[[string]$agentRisk]) { Deny 'Envelope risk exceeds the remote agent ceiling.' }
if ($envelope.delegation.network_access -ne 'none' -or $envelope.delegation.write_access -ne 'none') { Deny 'Remote delegation must remain read-only and without delegated network access.' }
foreach ($reference in @($envelope.input_refs)) {
  if ($reference.source_classification -notin @($agent.allowed_source_classifications)) { Deny 'Input source classification is not allowed for this agent.' }
}

$result = [PSCustomObject]@{
  allowed = $true
  reason = 'Pre-dispatch contract passes. This script never performs network dispatch.'
  agent_id = $AgentId
  workflow = 'knowledge_digest'
  next_required_step = 'Explicit human approval must enable the specific agent and network dispatch before any HTTP request.'
}
if ($AsJson) { $result | ConvertTo-Json -Depth 4 } else { $result | Format-List }
