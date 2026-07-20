<##
.SYNOPSIS
  Promotes a repeated, user-confirmed correction into a local preference.
.DESCRIPTION
  Promotion changes response friction only. It cannot change permissions,
  data scope, network, external actions, or confirmation requirements.
##>
param(
  [Parameter(Mandatory = $true)] [string]$CandidatePath,
  [Parameter(Mandatory = $true)] [ValidateSet('communication_language', 'response_style', 'speed_preference', 'quality_preference', 'collaboration_style', 'architecture_preference', 'shadow_second_opinion', 'tool_preference', 'workflow_order', 'workflow_default_parameters')] [string]$PreferenceKey,
  [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$PreferenceValue,
  [Parameter(Mandatory = $true)] [ValidateRange(3, 100)] [int]$ObservationCount,
  [ValidateSet('global', 'general', 'learning', 'commerce', 'documents', 'planning')] [string]$TaskDomain = 'global',
  [ValidateRange(1, 720)] [int]$ExpiresInDays = 90,
  [switch]$UserConfirmed,
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
if (-not $UserConfirmed) { throw 'User confirmation is required before preference promotion.' }
if ($PreferenceValue -match '(?i)(api[_-]?key|secret|password|cookie|bearer\s+[a-z0-9._-]{12,}|token\s*[:=]\s*[a-z0-9._-]{12,}|\b\d{11,}\b)') { throw 'Sensitive preference values must remain reference-only.' }
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$candidate = Get-Content -LiteralPath (Resolve-Path -LiteralPath $CandidatePath -ErrorAction Stop) -Raw -Encoding UTF8 | ConvertFrom-Json
if ($candidate.type -ne 'personal_preference_candidate' -or $candidate.source_type -ne 'explicit_user_correction' -or $candidate.status -ne 'candidate') { throw 'Only an explicit correction candidate can be promoted.' }
if ($candidate.permission_change_allowed -eq $true -or $candidate.data_scope_change_allowed -eq $true) { throw 'Permission or data scope changes cannot be promoted as personal preferences.' }
if ($ObservationCount -lt 3) { throw 'At least three observations are required.' }
$storePath = Join-Path $projectRoot '.qianlima\working\personal-preferences.json'
$storeDirectory = Split-Path -Parent $storePath
if (-not (Test-Path -LiteralPath $storeDirectory -PathType Container)) { New-Item -ItemType Directory -Path $storeDirectory -Force | Out-Null }
$store = if (Test-Path -LiteralPath $storePath -PathType Leaf) { Get-Content -LiteralPath $storePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [PSCustomObject]@{ schema_version = 1; preferences = @() } }
$now = (Get-Date).ToUniversalTime()
$preference = [ordered]@{ key = $PreferenceKey; value = $PreferenceValue.Trim(); state = 'validated'; domain = $TaskDomain; confidence = 'high'; source = 'explicit_user_correction'; source_candidate_id = $candidate.candidate_id; observation_count = $ObservationCount; user_confirmed = $true; last_used_at = $null; updated_at = $now.ToString('o'); expires_at = $now.AddDays($ExpiresInDays).ToString('o') }
$remaining = @($store.preferences | Where-Object { $_.key -ne $PreferenceKey })
$newStore = [ordered]@{ schema_version = 1; profile = 'personal'; preferences = @($remaining + [PSCustomObject]$preference); updated_at = (Get-Date).ToUniversalTime().ToString('o') }
[IO.File]::WriteAllText($storePath, ($newStore | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
$result = [PSCustomObject]@{ status = 'preference_promoted'; preference_key = $PreferenceKey; store_path = $storePath; user_confirmed = $true; permission_changed = $false; data_scope_changed = $false; confirmation_requirement_changed = $false }
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { $result | Format-List }
