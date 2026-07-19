<#
.SYNOPSIS
  Write one immutable Action Receipt per governed tool-call.
.DESCRIPTION
  Implements action-receipt-contract.json. Every tool-call (including denied
  and frozen ones) produces a receipt under
  run-traces/action-receipts/<work_node_id>/<action_id>.json.
#>
param(
  [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9._-]+$')] [string]$ActionId,
  [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')] [string]$WorkNodeId,
  [Parameter(Mandatory)] [string]$GrantId,
  [Parameter(Mandatory)] [string]$ToolName,
  [Parameter(Mandatory)] [ValidateRange(0, 100000)] [int]$Sequence,
  [ValidateSet('allow','deny','freeze')] [string]$Decision = 'allow',
  [Parameter(Mandatory)] [ValidatePattern('^sha256:[0-9a-f]{64}$')] [string]$InputHash,
  [ValidatePattern('^sha256:[0-9a-f]{64}$')] [string]$OutputHash = '',
  [ValidateRange(0, 3600000)] [int]$ElapsedMs = 0,
  [string]$CostProvider = 'local',
  [ValidateRange(0, [double]::MaxValue)] [double]$EstimatedUsd = 0,
  [string]$ConnectorReceipt = '',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$traceRoot = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'run-traces'
$nodeDir = Join-Path $traceRoot (Join-Path 'action-receipts' $WorkNodeId)
if (-not (Test-Path -LiteralPath $nodeDir -PathType Container)) {
  New-Item -ItemType Directory -Path $nodeDir -Force | Out-Null
}
$receiptPath = Join-Path $nodeDir "$ActionId.json"
if (Test-Path -LiteralPath $receiptPath) {
  Write-Error "Action Receipt already exists (immutable): $receiptPath"; exit 12
}
if ($Decision -ne 'allow' -and $OutputHash) {
  throw 'Denied or frozen actions cannot claim an output artifact.'
}

# The receipt directory is the append-only chain. Validate prior receipts before
# admitting the next one, so a missing or reordered action cannot be hidden by
# later receipts.
$prior = @()
foreach ($receiptFile in @(Get-ChildItem -LiteralPath $nodeDir -Filter '*.json' -File)) {
  try {
    $item = Get-Content -LiteralPath $receiptFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($item.work_node_id -ne $WorkNodeId -or $null -eq $item.sequence) {
      throw "receipt does not belong to this Work Node"
    }
    $prior += [int]$item.sequence
  } catch {
    throw "Existing Action Receipt chain is invalid at $($receiptFile.FullName): $($_.Exception.Message)"
  }
}
$prior = @($prior | Sort-Object)
for ($i = 0; $i -lt $prior.Count; $i++) {
  if ($prior[$i] -ne $i) { throw "Existing Action Receipt sequence has a gap or duplicate at $i." }
}
if ($Sequence -ne $prior.Count) {
  throw "Action Receipt sequence must be the next contiguous value ($($prior.Count)), received $Sequence."
}

$receipt = [ordered]@{
  schema_version    = 1
  receipt_type      = 'qianlima_action_receipt'
  action_id         = $ActionId
  work_node_id      = $WorkNodeId
  grant_id          = $GrantId
  tool_name         = $ToolName
  sequence          = $Sequence
  decision          = $Decision
  input_hash        = $InputHash
  output_hash       = if ($OutputHash) { $OutputHash } else { $null }
  elapsed_ms        = $ElapsedMs
  cost              = [ordered]@{ provider = $CostProvider; estimated_usd = $EstimatedUsd }
  connector_receipt = if ($ConnectorReceipt) { $ConnectorReceipt } else { $null }
  created_at        = (Get-Date).ToUniversalTime().ToString('o')
}
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Write-Host "Action Receipt written: $receiptPath"
if ($PassThru) { [PSCustomObject]$receipt }
