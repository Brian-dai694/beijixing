param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('asin', 'sku', 'campaign', 'keyword')]
  [string]$EntityType,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$')]
  [string]$EntityId,
  [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$cardPath = Join-Path $projectRoot "memory\cards\$EntityType\$EntityId.json"
if (-not (Test-Path -LiteralPath $cardPath -PathType Leaf)) {
  throw "Memory card not found: $cardPath"
}
$card = Get-Content -LiteralPath $cardPath -Raw -Encoding UTF8 | ConvertFrom-Json
$isFresh = ([datetime]$card.expires_at).ToUniversalTime() -gt (Get-Date).ToUniversalTime()
$result = [PSCustomObject]@{
  card_path = $cardPath
  freshness = if ($isFresh) { 'fresh' } else { 'stale' }
  reload_source_required = -not $isFresh
  card = $card
}
if ($AsJson) { $result | ConvertTo-Json -Depth 8 }
else {
  Write-Host "Memory card: $($card.entity_type)/$($card.entity_id) ($($result.freshness))"
  Write-Host "Source reload required: $($result.reload_source_required)"
}
