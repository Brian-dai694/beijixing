<# .SYNOPSIS Offline regression for the enterprise OneSkills Overlay. #>
param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$contract = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'oneskills-adapter-contract.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$gate = Join-Path $PSScriptRoot 'invoke-oneskills-admission-gate.ps1'
$cases = [System.Collections.Generic.List[object]]::new()
function Add-Case([string]$Name, [bool]$Passed) { $cases.Add([PSCustomObject]@{ name = $Name; passed = $Passed }) }
function Run-Gate([string[]]$Arguments) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate @Arguments -PassThru 2>&1)
  $code = $LASTEXITCODE; $ErrorActionPreference = $old; $value = $null
  try { $value = ($out -join "`n") | ConvertFrom-Json } catch {}
  [PSCustomObject]@{ code = $code; value = $value }
}
$base = @('-TaskId', 'task-1', '-GrantId', 'grant-1', '-AdmissionEvidenceRef', 'evidence-1', '-AdmissionDecision', 'approved', '-DataClassification', 'internal_sanitized', '-SanitizedEvidencePack', '-ActiveTaskGrant')
Add-Case 'candidate_is_not_installed' ($contract.status -eq 'candidate_ecosystem_not_installed')
Add-Case 'fastmcp_http_is_disabled' ($contract.transport.fastmcp_http -eq 'disabled')
Add-Case 'streamable_http_is_disabled' ($contract.transport.streamable_http -eq 'disabled')
Add-Case 'public_unauthenticated_bind_is_denied' ($contract.transport.public_bind -eq 'deny' -and $contract.transport.unauthenticated_http -eq 'deny')
$proposal = Run-Gate (@('-Mode', 'resource_proposal', '-TaskLevel', 'L2') + $base)
Add-Case 'resource_proposal_is_brokered_and_non_executing' ($proposal.code -eq 0 -and $proposal.value.status -eq 'proposal_admitted' -and -not $proposal.value.execution_authorized -and -not $proposal.value.external_calls)
$expert = Run-Gate (@('-Mode', 'expert_proposal', '-TaskLevel', 'L3') + $base)
Add-Case 'expert_proposal_is_brokered_and_non_executing' ($expert.code -eq 0 -and $expert.value.proposal_only -and -not $expert.value.processes_started)
$http = Run-Gate (@('-Mode', 'resource_proposal', '-TaskLevel', 'L2', '-Transport', 'http') + $base)
Add-Case 'http_transport_is_mechanically_denied' ($http.code -ne 0 -and @($http.value.reasons) -contains 'fastmcp_http_transport_disabled')
$sensitive = Run-Gate @('-Mode', 'resource_proposal', '-TaskLevel', 'L2', '-TaskId', 'task-1', '-GrantId', 'grant-1', '-AdmissionEvidenceRef', 'evidence-1', '-AdmissionDecision', 'approved', '-DataClassification', 'confidential_reference_only', '-SanitizedEvidencePack', '-ActiveTaskGrant')
Add-Case 'raw_sensitive_data_is_denied' ($sensitive.code -ne 0 -and @($sensitive.value.reasons) -contains 'raw_sensitive_data_not_admissible')
$executorIncomplete = Run-Gate (@('-Mode', 'executor', '-TaskLevel', 'L3') + $base)
Add-Case 'executor_without_L4_controls_is_denied' ($executorIncomplete.code -ne 0 -and @($executorIncomplete.value.reasons) -contains 'executor_requires_L4')
$executor = Run-Gate (@('-Mode', 'executor', '-TaskLevel', 'L4', '-WorkOrderId', 'work-1', '-HumanApproval', '-PreflightEvidence', '-IndependentVerifier', '-VerifiedRunnerAttestation') + $base)
Add-Case 'l4_executor_remains_runner_candidate_only' ($executor.code -eq 0 -and $executor.value.status -eq 'conditional' -and -not $executor.value.execution_authorized -and -not $executor.value.listeners_opened)
$failed = @($cases | Where-Object { -not $_.passed })
$result = [PSCustomObject]@{ passed = ($failed.Count -eq 0); cases = @($cases); listeners_opened = $false; processes_started = $false; external_calls = $false; permissions_granted = $false }
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { $cases | Format-Table -AutoSize }
if ($failed.Count -gt 0) { throw "OneSkills admission regression failed: $($failed.name -join ', ')" }
