param(
  [ValidateSet('Start', 'Reconnect', 'Diagnostics', 'Stop')]
  [string]$Action = 'Start',
  [ValidateRange(1024, 65535)] [int]$Port = 15722,
  [ValidatePattern('^[A-Za-z0-9_-]{3,80}$')] [string]$AgentId = 'local-readonly-evidence-checker',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$onboardScript = Join-Path $PSScriptRoot 'new-local-readonly-a2a-agent.ps1'
$serverScript = Join-Path $PSScriptRoot 'serve-local-readonly-a2a-agent.ps1'
$agentRoot = Join-Path $projectRoot ('.qianlima\local-a2a-agents\' + $AgentId)
$serverInfoPath = Join-Path $agentRoot 'server.json'
$cardUrl = "http://127.0.0.1:$Port/.well-known/agent-card.json"

function Get-ServiceProcess {
  if (-not (Test-Path -LiteralPath $serverInfoPath -PathType Leaf)) { return $null }
  try { $info = Get-Content -LiteralPath $serverInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
  if ($info.port -ne $Port) { return $null }
  $process = Get-Process -Id $info.pid -ErrorAction SilentlyContinue
  if ($null -eq $process) { return $null }
  if ($process.Path -and $process.Path -ne (Join-Path $PSHOME 'powershell.exe')) { return $null }
  return $process
}

function Test-Health {
  try { return (Invoke-WebRequest -UseBasicParsing -Uri $cardUrl -TimeoutSec 1).StatusCode -eq 200 } catch { return $false }
}

function Get-Status([string]$Status, [string]$Diagnostic) {
  [PSCustomObject]@{
    agent_id = $AgentId
    role = 'local-readonly-evidence-checker'
    status = $Status
    connected = $Status -eq 'connected'
    network_access = 'none'
    write_access = 'none'
    user_actions = @('reconnect', 'copy_diagnostics')
    diagnostic = $Diagnostic
  }
}

if ($Action -eq 'Diagnostics') {
  $process = Get-ServiceProcess
  $status = if ($process -and (Test-Health)) { 'connected' } else { 'disconnected' }
  $result = Get-Status $status $(if ($status -eq 'connected') { 'Local health check passed.' } else { 'No healthy local service detected.' })
  if ($PassThru) { $result | ConvertTo-Json -Depth 5 } else { $result | Format-List }; exit 0
}
if ($Action -eq 'Stop') {
  $process = Get-ServiceProcess
  if ($process) { Stop-Process -Id $process.Id -Force }
  $result = Get-Status 'disconnected' 'Local service stopped.'
  if ($PassThru) { $result | ConvertTo-Json -Depth 5 } else { $result | Format-List }; exit 0
}

$cardPath = Join-Path $agentRoot 'agent-card.json'
$registryPath = Join-Path $projectRoot '.qianlima\local-a2a-agents.json'
$firstSetup = -not (Test-Path -LiteralPath $cardPath -PathType Leaf) -or -not (Test-Path -LiteralPath $registryPath -PathType Leaf)
if ($firstSetup) { & $onboardScript -AgentId $AgentId -Port $Port | Out-Null }
else { & $onboardScript -AgentId $AgentId -Port $Port -SkipContractTest | Out-Null }
$existing = Get-ServiceProcess
if ($existing -and (Test-Health)) {
  $result = Get-Status 'connected' 'Local read-only evidence checker is connected.'
  if ($PassThru) { $result | ConvertTo-Json -Depth 5 } else { $result | Format-List }; exit 0
}
if ($Action -eq 'Reconnect' -and $existing) { Stop-Process -Id $existing.Id -Force; Start-Sleep -Milliseconds 200 }
$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$serverScript`" -Port $Port -AgentId $AgentId"
$powerShellPath = Join-Path $PSHOME 'powershell.exe'
$startInfo = New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName = [Environment]::GetEnvironmentVariable('COMSPEC')
$startInfo.Arguments = "/c start `"`" /b `"$powerShellPath`" $arguments >nul 2>nul"
$startInfo.WorkingDirectory = $projectRoot
$startInfo.UseShellExecute = $true
$startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
[Diagnostics.Process]::Start($startInfo) | Out-Null
$deadline = (Get-Date).AddSeconds(5)
$ready = $false
while ((Get-Date) -lt $deadline -and -not $ready) { Start-Sleep -Milliseconds 150; $ready = Test-Health }
if (-not $ready) { throw 'Local read-only evidence checker did not connect. Use diagnostics for the local error.' }
$result = Get-Status 'connected' 'Local read-only evidence checker is connected.'
if ($PassThru) { $result | ConvertTo-Json -Depth 5 } else { $result | Format-List }
