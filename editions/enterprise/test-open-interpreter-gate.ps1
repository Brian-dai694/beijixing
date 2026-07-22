<# .SYNOPSIS Offline regression for the Open Interpreter enterprise Runner Overlay. #>
param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$contract = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'open-interpreter-runner-contract.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$gate = Join-Path $PSScriptRoot 'invoke-open-interpreter-gate.ps1'
$cases = [System.Collections.Generic.List[object]]::new()
function Add-Case([string]$Name, [bool]$Passed) { $cases.Add([PSCustomObject]@{ name = $Name; passed = $Passed }) }
function Run-Gate([string[]]$Arguments) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $hostPath = Join-Path $PSHOME $(if ($env:OS -eq 'Windows_NT') { 'powershell.exe' } else { 'pwsh' })
  $out = @(& $hostPath -NoProfile -ExecutionPolicy Bypass -File $gate @Arguments -PassThru 2>&1)
  $code = $LASTEXITCODE; $ErrorActionPreference = $old; $value = $null
  try { $value = ($out -join "`n") | ConvertFrom-Json } catch {}
  [PSCustomObject]@{ code = $code; value = $value }
}
$base = @('-TaskId', 'task-1', '-WorkOrderId', 'work-1', '-WorkOrderTaskId', 'task-1', '-GrantId', 'grant-1', '-GrantTaskId', 'task-1', '-AdapterAdmitted', '-GrantActive', '-BudgetAvailable', '-AuditSinkReady', '-RevocationPathReady')
$readonly = $base + @('-RiskLevel', 'L2', '-RequestedCapability', 'csv_readonly_analysis', '-DataClassification', 'internal_sanitized')
Add-Case 'runtime_is_discover_only_and_not_installed' ($contract.status -eq 'discover_only_not_installed')
Add-Case 'host_and_business_authority_are_absent' ($contract.business_authority -eq 'none' -and $contract.production_authority -eq 'none')
$plan = Run-Gate (@('-Phase', 'Plan') + $readonly)
Add-Case 'readonly_plan_is_allowed_without_execution' ($plan.code -eq 0 -and $plan.value.status -eq 'plan_allowed' -and -not $plan.value.execution_authorized -and -not $plan.value.process_started)
$network = Run-Gate (@('-Phase', 'Plan', '-NetworkAccess', 'allowlisted') + $readonly)
Add-Case 'network_is_denied' ($network.code -ne 0 -and @($network.value.reasons) -contains 'network_access_denied')
$write = Run-Gate (@('-Phase', 'Plan', '-WriteAccess', 'task_workspace') + $readonly)
Add-Case 'write_is_denied_initially' ($write.code -ne 0 -and @($write.value.reasons) -contains 'write_access_denied_initial_release')
$mismatch = Run-Gate @('-Phase', 'Plan', '-RiskLevel', 'L2', '-RequestedCapability', 'csv_readonly_analysis', '-TaskId', 'task-1', '-WorkOrderId', 'work-1', '-WorkOrderTaskId', 'task-2', '-GrantId', 'grant-1', '-GrantTaskId', 'task-1', '-AdapterAdmitted', '-GrantActive', '-BudgetAvailable', '-AuditSinkReady', '-RevocationPathReady')
Add-Case 'task_binding_mismatch_is_denied' ($mismatch.code -ne 0 -and @($mismatch.value.reasons) -contains 'task_binding_mismatch')
$browser = Run-Gate (@('-Phase', 'Plan') + $base + @('-RiskLevel', 'L2', '-RequestedCapability', 'browser_control', '-DataClassification', 'internal_sanitized'))
Add-Case 'browser_and_erp_class_capabilities_are_denied' ($browser.code -ne 0 -and @($browser.value.reasons) -contains 'capability_not_in_initial_allowlist')
$secret = Run-Gate (@('-Phase', 'Plan') + $base + @('-RiskLevel', 'L2', '-RequestedCapability', 'csv_readonly_analysis', '-DataClassification', 'restricted_secret'))
Add-Case 'restricted_secret_is_denied' ($secret.code -ne 0 -and @($secret.value.reasons) -contains 'data_classification_denied')
$execute = Run-Gate (@('-Phase', 'Execute', '-AttestationId', 'attestation-1', '-AttestationVerified') + $readonly)
Add-Case 'execute_remains_disabled_even_with_attestation' ($execute.code -ne 0 -and @($execute.value.reasons) -contains 'open_interpreter_execution_disabled_this_release' -and -not $execute.value.process_started)
Add-Case 'command_success_is_not_business_verification' ($contract.step_result.success_semantics -eq 'command_success_is_not_business_verification')
$failed = @($cases | Where-Object { -not $_.passed })
$result = [PSCustomObject]@{ passed = ($failed.Count -eq 0); cases = @($cases); listeners_opened = $false; processes_started = $false; external_calls = $false; files_written = $false; permissions_granted = $false }
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { $cases | Format-Table -AutoSize }
if ($failed.Count -gt 0) { throw "Open Interpreter gate regression failed: $($failed.name -join ', ')" }
