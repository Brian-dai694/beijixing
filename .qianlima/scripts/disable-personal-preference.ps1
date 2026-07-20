param(
  [Parameter(Mandatory = $true)] [ValidateSet('communication_language', 'response_style', 'speed_preference', 'quality_preference', 'collaboration_style', 'architecture_preference', 'shadow_second_opinion', 'tool_preference', 'workflow_order', 'workflow_default_parameters')] [string]$PreferenceKey,
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$storePath = Join-Path $projectRoot '.qianlima\working\personal-preferences.json'
if (-not (Test-Path -LiteralPath $storePath -PathType Leaf)) { throw 'Preference does not exist.' }
$store = Get-Content -LiteralPath $storePath -Raw -Encoding UTF8 | ConvertFrom-Json
$found = @($store.preferences | Where-Object { $_.key -eq $PreferenceKey })
if ($found.Count -eq 0) { throw 'Preference does not exist.' }
$now = (Get-Date).ToUniversalTime()
$updated = @($store.preferences | ForEach-Object { if ($_.key -eq $PreferenceKey) { [PSCustomObject]@{ key=$_.key; value=$_.value; state='disabled'; domain=$_.domain; confidence=$_.confidence; source=$_.source; source_candidate_id=$_.source_candidate_id; observation_count=$_.observation_count; user_confirmed=$_.user_confirmed; last_used_at=$_.last_used_at; updated_at=$_.updated_at; expires_at=$_.expires_at; disabled_at=$now.ToString('o') } } else { $_ } })
$newStore = [ordered]@{ schema_version=1; profile='personal'; preferences=$updated; updated_at=$now.ToString('o') }
[IO.File]::WriteAllText($storePath, ($newStore | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
$result = [PSCustomObject]@{ status='preference_disabled'; preference_key=$PreferenceKey; selected_by_runtime=$false; permission_changed=$false; data_scope_changed=$false }
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { $result | Format-List }
