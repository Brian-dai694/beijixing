param(
  [Parameter(Mandatory = $true)] [ValidateSet('communication_language', 'response_style', 'speed_preference', 'quality_preference', 'collaboration_style', 'architecture_preference', 'shadow_second_opinion', 'tool_preference', 'workflow_order', 'workflow_default_parameters')] [string]$PreferenceKey,
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$storePath = Join-Path $projectRoot '.qianlima\working\personal-preferences.json'
$store = if (Test-Path -LiteralPath $storePath -PathType Leaf) { Get-Content -LiteralPath $storePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [PSCustomObject]@{ schema_version = 1; profile = 'personal'; preferences = @() } }
$remaining = @($store.preferences | Where-Object { $_.key -ne $PreferenceKey })
$newStore = [ordered]@{ schema_version = 1; profile = 'personal'; preferences = $remaining; updated_at = (Get-Date).ToUniversalTime().ToString('o') }
[IO.File]::WriteAllText($storePath, ($newStore | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
$result = [PSCustomObject]@{ status = 'preference_removed'; preference_key = $PreferenceKey; active_preference_changed = $true; remaining_count = $remaining.Count }
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { $result | Format-List }
