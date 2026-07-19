<#
.SYNOPSIS
  Regression test for Enterprise launcher runtime selection.
.DESCRIPTION
  Ensures the shared start path uses the active PowerShell implementation and
  that the bash wrapper remains a pwsh-only preflight launcher. This test does
  not require Docker or attempt to start a Runner.
#>
param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$enterpriseRoot = $PSScriptRoot
$powerShellLauncher = Get-Content -LiteralPath (Join-Path $enterpriseRoot 'start-enterprise.ps1') -Raw -Encoding UTF8
$bashLauncher = Get-Content -LiteralPath (Join-Path $enterpriseRoot 'start-enterprise.sh') -Raw -Encoding UTF8
$cases = [System.Collections.Generic.List[object]]::new()

function Add-Case([string]$Name, [bool]$Passed) {
  $cases.Add([PSCustomObject]@{ name = $Name; passed = $Passed })
}

Add-Case 'core_runtime_uses_pwsh' ($powerShellLauncher -match "PSVersionTable\.PSEdition -eq 'Core'.+return 'pwsh'")
Add-Case 'windows_compatibility_keeps_windows_powershell' ($powerShellLauncher -match "env:OS -eq 'Windows_NT'.+return 'powershell\.exe'")
Add-Case 'child_profile_uses_selected_runtime' ($powerShellLauncher -match '& \$powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File \$profileTest')
Add-Case 'child_environment_gate_uses_selected_runtime' ($powerShellLauncher -match '& \$powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File \$environmentTest')
Add-Case 'child_core_start_uses_selected_runtime' ($powerShellLauncher -match '& \$powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File \$coreStart')
Add-Case 'bash_wrapper_requires_pwsh' ($bashLauncher -match 'command -v pwsh' -and $bashLauncher -match 'exec pwsh -NoProfile -File')

$failed = @($cases | Where-Object { -not $_.passed })
$result = [PSCustomObject]@{
  passed = ($failed.Count -eq 0)
  external_calls = $false
  runner_started = $false
  cases = @($cases)
}
if ($PassThru) { $result | ConvertTo-Json -Depth 6 } else { $cases | Format-Table -AutoSize }
if ($failed.Count -gt 0) { throw ('Enterprise launcher regression failed: ' + ($failed.name -join ', ')) }
