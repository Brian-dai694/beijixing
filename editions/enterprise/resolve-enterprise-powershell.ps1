<##
.SYNOPSIS
  Resolves the current PowerShell executable for cross-platform child calls.
##>
function Get-EnterprisePowerShellCommand {
  $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $pwsh) { return $pwsh.Source }
  $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $windowsPowerShell) { return $windowsPowerShell.Source }
  throw 'PowerShell 7 (pwsh) or Windows PowerShell (powershell.exe) is required.'
}
