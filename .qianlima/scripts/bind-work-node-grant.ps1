<#
.SYNOPSIS
  Broker-only dispatch gate binding one issued Delegation Grant to one Work Node.
.DESCRIPTION
  The binding is the transition from a planned R&D milestone to executable work.
  It proves that the Grant is active, unexpired, and scoped to this exact node
  before any runtime adapter or governed capability can run.
#>
param(
  [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')] [string]$WorkNodeId,
  [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9._-]+$')] [string]$GrantId,
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$traceRoot = Join-Path $projectRoot '.qianlima\run-traces'
$nodePath = Join-Path $traceRoot "work-nodes/$WorkNodeId.json"
$grantPath = Join-Path $traceRoot "delegation-grants/$GrantId.json"
if (-not (Test-Path -LiteralPath $nodePath)) { throw "Work Node not found: $WorkNodeId" }
if (-not (Test-Path -LiteralPath $grantPath)) { throw "Delegation Grant not found: $GrantId" }

$node = Get-Content -LiteralPath $nodePath -Raw -Encoding UTF8 | ConvertFrom-Json
$grant = Get-Content -LiteralPath $grantPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($node.status -notin @('draft','blocked')) { throw "Work Node is not dispatchable (status=$($node.status))." }
if ($grant.grant_id -ne $GrantId -or $grant.status -ne 'issued') { throw "Grant is not active: $GrantId" }
if ([datetime]$grant.expires_at -le (Get-Date).ToUniversalTime()) { throw "Grant is expired: $GrantId" }
if ($grant.task_id -ne $WorkNodeId) { throw 'P0 requires the Grant task_id to equal the Work Node id.' }

$riskRank = @{ L0 = 0; L1 = 1; L2 = 2; L3 = 3; L4 = 4 }
if ($riskRank[[string]$grant.risk_ceiling] -gt $riskRank[[string]$node.risk_ceiling]) {
  throw "Grant risk ceiling exceeds Work Node ceiling: $($grant.risk_ceiling) > $($node.risk_ceiling)"
}

$node.grant_id = $GrantId
$node.status = 'granted'
[IO.File]::WriteAllText($nodePath, ($node | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

& (Join-Path $PSScriptRoot 'write-audit-event.ps1') -EventType 'grant_checked' -Decision allow `
  -TaskId $WorkNodeId -GrantId $GrantId -Reason 'Work Node Grant binding accepted by Broker.' | Out-Null

$result = [PSCustomObject]@{ work_node_id = $WorkNodeId; grant_id = $GrantId; status = 'granted' }
if ($PassThru) { $result } else { Write-Host "Work Node Grant bound: $WorkNodeId -> $GrantId" }
