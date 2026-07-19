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

$actionSource = Read-Source '.qianlima\scripts\new-action-receipt.ps1'
$fffSource = Read-Source '.qianlima\scripts\invoke-fff-scoped.ps1'
$verifySource = Read-Source '.qianlima\scripts\verify-work-node.ps1'
$bindSource = Read-Source '.qianlima\scripts\bind-work-node-grant.ps1'
$projectionSource = Read-Source '.qianlima\scripts\new-manager-projection.ps1'

Require ($actionSource -match 'next contiguous value') 'Action Receipt writer must reject sequence gaps.'
Require ($fffSource -match 'grant\.expires_at') 'fff gateway must reject expired Grants.'
Require ($fffSource -match "allowed_tools\) -notcontains 'fff'") 'fff gateway must require the fff capability in the Grant.'
Require ($verifySource -match "EventType 'verification_completed'") 'Verifier must emit the canonical verification event.'
Require ($verifySource -match 'receipt_sequence_gap_or_duplicate') 'Verifier must independently check receipt continuity.'
Require ($bindSource -match "status = 'granted'") 'Broker binding must move the node to granted.'
Require ($projectionSource -match 'acceptedVerification') 'Manager projection must require accepted verification evidence.'
Require ($projectionSource -match "EventType 'manager_projection_published'") 'Manager projection must emit an audit event.'

$scripts = @(
  '.qianlima\scripts\new-action-receipt.ps1',
  '.qianlima\scripts\invoke-fff-scoped.ps1',
  '.qianlima\scripts\verify-work-node.ps1',
  '.qianlima\scripts\bind-work-node-grant.ps1',
  '.qianlima\scripts\new-manager-projection.ps1'
)
foreach ($script in $scripts) {
  $tokens = $null; $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot $script), [ref]$tokens, [ref]$errors)
  Require ($errors.Count -eq 0) "PowerShell parser rejected $script"
}

Write-Host 'R&D P0 governance contract regression passed.'
