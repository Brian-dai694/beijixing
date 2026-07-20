<#
.SYNOPSIS
  Read-only rejection regression for Sandbox Attestation.
  No candidate, attestation, Runner, or audit record is created.
#>
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Read-Source([string]$RelativePath) { Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Raw -Encoding UTF8 }

$contract = Get-Content -LiteralPath (Join-Path $projectRoot '.qianlima\specifications\sandbox-attestation-contract.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$candidate = Read-Source '.qianlima\scripts\new-pi-omp-attestation-candidate.ps1'
$validator = Read-Source '.qianlima\scripts\verify-sandbox-attestation.ps1'
$runner = Read-Source '.qianlima\scripts\invoke-governed-runner.ps1'

Require (@($contract.candidate_status) -contains 'pending') 'Candidate status must be pending.'
Require ((@($contract.invariants) -match 'manual switch').Count -gt 0) 'Contract must reject manual verified switches.'
Require ($candidate -match "status='pending'") 'Candidate generator must emit pending status.'
Require ($candidate -notmatch "status='verified'") 'Candidate generator must never emit verified status.'
Require ($validator -match 'attestation_not_verified') 'Validator must reject pending candidates.'
Require ($validator -match 'attestation_outlives_grant') 'Validator must reject attestations outliving Grants.'
Require ($validator -match 'attestation_task_mismatch') 'Validator must reject task mismatches.'
Require ($validator -match 'attestation_grant_mismatch') 'Validator must reject Grant mismatches.'
Require ($validator -match 'process_started=\$false') 'Validator must not start a process.'
Require ($runner -match "attestation.status -ne 'verified'") 'Runner gate must require verified Attestation.'

$output = @()
$exitCode = 0
try {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-sandbox-attestation.ps1') `
    -RunnerId 'runner-does-not-exist' -WorkOrderPath 'missing.json' -GrantPath 'missing.json' -AttestationPath 'missing.json' 2>&1)
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = $previous
} catch {
  $output += ($_ | Out-String)
  $exitCode = 1
  $ErrorActionPreference = 'Stop'
}
Require ($exitCode -ne 0 -and ($output -join "`n") -match 'Unknown Runner') 'Unknown Runner rejection path must remain closed.'

Write-Host 'Sandbox Attestation rejection regression passed.'
