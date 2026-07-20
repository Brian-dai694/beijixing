param(
  [Parameter(Mandatory = $true)] [ValidateSet('communication_language', 'response_style', 'speed_preference', 'quality_preference', 'collaboration_style', 'architecture_preference', 'shadow_second_opinion', 'tool_preference', 'workflow_order', 'workflow_default_parameters')] [string]$PreferenceKey,
  [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$PreferenceValue,
  [switch]$UserConfirmed,
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
if (-not $UserConfirmed) { throw 'User confirmation is required before editing a preference.' }
if ($PreferenceValue -match '(?i)(api[_-]?key|secret|password|cookie|bearer\s+[a-z0-9._-]{12,}|token\s*[:=]\s*[a-z0-9._-]{12,}|\b\d{11,}\b)') { throw 'Sensitive preference values must remain reference-only.' }
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$storePath = Join-Path $projectRoot '.qianlima\working\personal-preferences.json'
if (-not (Test-Path -LiteralPath $storePath -PathType Leaf)) { throw 'Preference does not exist.' }
$store = Get-Content -LiteralPath $storePath -Raw -Encoding UTF8 | ConvertFrom-Json
$found = @($store.preferences | Where-Object { $_.key -eq $PreferenceKey })
if ($found.Count -eq 0) { throw 'Preference does not exist.' }
$now = (Get-Date).ToUniversalTime()
$updated = @($store.preferences | ForEach-Object { if ($_.key -eq $PreferenceKey) { [PSCustomObject]@{ key=$_.key; value=$PreferenceValue.Trim(); state='validated'; domain=$_.domain; confidence=$_.confidence; source='user_edit'; source_candidate_id=$_.source_candidate_id; observation_count=$_.observation_count; user_confirmed=$true; last_used_at=$_.last_used_at; updated_at=$now.ToString('o'); expires_at=$_.expires_at } } else { $_ } })
$newStore = [ordered]@{ schema_version=1; profile='personal'; preferences=$updated; updated_at=$now.ToString('o') }
[IO.File]::WriteAllText($storePath, ($newStore | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
$result = [PSCustomObject]@{ status='preference_edited'; preference_key=$PreferenceKey; permission_changed=$false; data_scope_changed=$false; confirmation_requirement_changed=$false }
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { $result | Format-List }
