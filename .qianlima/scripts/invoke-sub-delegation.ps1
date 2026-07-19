<#
.SYNOPSIS
  Execute one bounded tool call under a pre-signed delegation grant.
.DESCRIPTION
  Validates the grant locally — no per-call Broker round-trip. The Broker's authority is
  exercised at grant-sign time; subsequent calls only need the local grant file.
  Every call (allow or deny) writes to audit-events.jsonl, making the event stream live.
  This is the Phase-1 implementation of grant-driven low-round-trip sub-delegation.
.EXAMPLE
  .\invoke-sub-delegation.ps1 -GrantId g1 -TaskId t1 -ToolCall read_selected_sources -AsJson
#>
param(
  [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9._-]+$')] [string]$GrantId,
  [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9._-]+$')] [string]$TaskId,
  [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9._-]+$')] [string]$ToolCall,
  [string]$DataRef = '',
  [ValidatePattern('^[a-zA-Z0-9._-]*$')] [string]$AgentId = '',
  [switch]$AsJson,
  [switch]$NoExit
)

$ErrorActionPreference = 'Stop'
$psExe       = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$grantRoot   = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\delegation-grants'))
$counterRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\sub-delegation-counters'))
$revPath     = Join-Path $projectRoot '.qianlima\run-traces\grant-revocations.jsonl'
$auditScript = Join-Path $PSScriptRoot 'write-audit-event.ps1'

function Write-AuditCall([string]$Decision, [string]$Reason) {
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $auditScript,
    '-EventType', 'sub_delegation_tool_call', '-Decision', $Decision,
    '-TaskId', $TaskId, '-GrantId', $GrantId, '-Reason', $Reason)
  if ($AgentId) { $a += @('-AgentId', $AgentId) }
  if ($DataRef)  { $a += @('-DataRef', $DataRef) }
  & $psExe @a | Out-Null
}

function Deny-Exit([string]$Reason) {
  Write-AuditCall 'deny' $Reason
  $r = [PSCustomObject]@{ allowed = $false; grant_id = $GrantId; task_id = $TaskId
    tool_call = $ToolCall; calls_used = $null; calls_remaining = $null; reason = $Reason }
  if ($AsJson) { $r | ConvertTo-Json -Depth 4 } else { $r }
  if (-not $NoExit) { exit 20 }
}

# All checks are local — no Broker round-trip per call.
$grantPath = Join-Path $grantRoot "$GrantId.json"
if (-not (Test-Path -LiteralPath $grantPath -PathType Leaf)) { Deny-Exit "Grant not found: $GrantId"; return }
$grant = Get-Content -LiteralPath $grantPath -Raw -Encoding UTF8 | ConvertFrom-Json
