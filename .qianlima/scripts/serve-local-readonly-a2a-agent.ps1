param(
  [ValidateRange(1024, 65535)] [int]$Port = 15722,
  [ValidatePattern('^[A-Za-z0-9_-]{3,80}$')] [string]$AgentId = 'local-readonly-evidence-checker'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$agentRoot = Join-Path $projectRoot ('.qianlima\local-a2a-agents\' + $AgentId)
$cardPath = Join-Path $agentRoot 'agent-card.json'
$serverPath = Join-Path $agentRoot 'server.json'
$errorPath = Join-Path $agentRoot 'server-error.log'
if (-not (Test-Path -LiteralPath $cardPath -PathType Leaf)) { throw 'Create the local Agent Card before starting the service.' }

function Write-HttpJson([IO.Stream]$Stream, [int]$StatusCode, $Body) {
  $json = $Body | ConvertTo-Json -Depth 12 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $reason = if ($StatusCode -eq 200) { 'OK' } elseif ($StatusCode -eq 400) { 'Bad Request' } elseif ($StatusCode -eq 403) { 'Forbidden' } else { 'Not Found' }
  $header = "HTTP/1.1 $StatusCode $reason`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
  $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)
  $Stream.Write($bytes, 0, $bytes.Length)
  $Stream.Flush()
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
$listener.Start()
[IO.File]::WriteAllText($serverPath, ([ordered]@{ agent_id = $AgentId; pid = $PID; port = $Port; bind_address = '127.0.0.1'; started_at = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    $stream = $null
    $reader = $null
    try {
      $stream = $client.GetStream()
      $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $false, 4096, $true)
      $requestLine = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }
      $parts = $requestLine.Split(' ')
      if ($parts.Count -lt 2) { Write-HttpJson $stream 400 @{ error = 'invalid_request' }; continue }
      $method = $parts[0]; $path = $parts[1]
      $contentLength = 0
      while ($true) {
        $headerLine = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($headerLine)) { break }
        if ($headerLine -match '^Content-Length:\s*(\d+)$') { $contentLength = [int]$Matches[1] }
      }
      if ($contentLength -gt 65536) { Write-HttpJson $stream 400 @{ error = 'request_too_large' }; continue }
      $raw = ''
      if ($contentLength -gt 0) {
        $buffer = New-Object char[] $contentLength
        [void]$reader.ReadBlock($buffer, 0, $contentLength)
        $raw = -join $buffer
      }
      if ($method -eq 'GET' -and $path -eq '/.well-known/agent-card.json') {
        Write-HttpJson $stream 200 (Get-Content -LiteralPath $cardPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        continue
      }
      if ($method -ne 'POST' -or $path -ne '/a2a') { Write-HttpJson $stream 404 @{ error = 'not_found' }; continue }
      try { $rpc = $raw | ConvertFrom-Json } catch { Write-HttpJson $stream 400 @{ error = 'invalid_json' }; continue }
      if ($rpc.jsonrpc -ne '2.0' -or $rpc.method -notin @('tasks/send', 'tasks/get')) {
        Write-HttpJson $stream 400 @{ jsonrpc = '2.0'; id = $rpc.id; error = @{ code = -32601; message = 'Only bounded task methods are available.' } }
        continue
      }
      $paramsJson = if ($rpc.params) { $rpc.params | ConvertTo-Json -Depth 8 -Compress } else { '{}' }
      if ($paramsJson -match '"risk_ceiling"\s*:\s*"L4"' -or $paramsJson -match '"network_access"\s*:\s*"(?!none)' -or $paramsJson -match '"write_access"\s*:\s*"(?!none)') {
        Write-HttpJson $stream 403 @{ jsonrpc = '2.0'; id = $rpc.id; error = @{ code = -32001; message = 'Read-only local Agent rejects elevated permissions.' } }
        continue
      }
      $taskId = "local-readonly-$([Guid]::NewGuid().ToString('n'))"
      $result = @{ id = $taskId; status = @{ state = 'completed' }; artifacts = @(@{ name = 'verification_receipt'; parts = @(@{ kind = 'data'; data = @{ status = 'completed'; summary = 'Bounded local read-only verification completed. Raw input was not retained.' } }) }) }
      Write-HttpJson $stream 200 @{ jsonrpc = '2.0'; id = $rpc.id; result = $result }
    } finally {
      if ($reader) { $reader.Dispose() }
      if ($client) { $client.Close() }
    }
  }
} catch {
  $errorText = ($_ | Out-String)
  [IO.File]::WriteAllText($errorPath, $errorText, [Text.UTF8Encoding]::new($false))
  throw
} finally {
  $listener.Stop()
}
