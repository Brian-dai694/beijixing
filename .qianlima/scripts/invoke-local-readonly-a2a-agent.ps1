<#
.SYNOPSIS
  Runs the registered local read-only A2A-compatible agent without a listener.
.DESCRIPTION
  This is the runtime entry point used by Qianlima after natural-language routing.
  It never requires an address from the user and delegates only to the bounded
  local evidence checker through the existing local contract mock.
#>
param(
  [Parameter(Mandatory = $true)] [string]$EnvelopePath,
  [ValidatePattern('^[A-Za-z0-9_-]{3,80}$')] [string]$AgentId = 'local-readonly-evidence-checker',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$registryPath = Join-Path $projectRoot '.qianlima\local-a2a-agents.json'
$mockScript = Join-Path $PSScriptRoot 'invoke-a2a-local-mock.ps1'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) { throw 'No local A2A agent is registered.' }
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$agent = @($registry.agents | Where-Object { $_.id -eq $AgentId }) | Select-Object -First 1
if ($null -eq $agent -or $agent.status -ne 'registered_local_only') { throw 'Requested local agent is not available.' }
if ($agent.dispatch_enabled -ne $false -or $agent.network_access -ne 'none' -or $agent.write_access -ne 'none') { throw 'Local agent registration violates the read-only policy.' }

$result = & $mockScript -EnvelopePath $EnvelopePath -PassThru | ConvertFrom-Json
if ($PassThru) { $result | ConvertTo-Json -Depth 6 } else { $result | Format-List }
