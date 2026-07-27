param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$indexPath = Join-Path $PSScriptRoot 'governance-handbook-index.json'
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifestRoot = [IO.Path]::GetFullPath((Join-Path $root '.qianlima/run-traces/enterprise-handbook/sync')) + [IO.Path]::DirectorySeparatorChar
$entries = [System.Collections.Generic.List[object]]::new()
foreach ($relativeCard in @($index.cards)) {
  $cardPath = Join-Path $root $relativeCard
  $card = Get-Content -LiteralPath $cardPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $sources = [System.Collections.Generic.List[object]]::new()
  foreach ($ref in @($card.implementation_refs) + @($card.test_refs)) {
    $path = if ($ref -is [string]) { $ref } else { [string]$ref.path }
    $sourcePath = Join-Path $root ($path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw ('Handbook source missing: ' + $path) }
    $hash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sources.Add([ordered]@{ path = $path; anchor = if ($ref -is [string]) { $null } else { [string]$ref.anchor }; sha256 = 'sha256:' + $hash; anchor_status = 'declared_not_automatically_proven'; dropped_calls = @(); source_is_authoritative = $true })
  }
  $entries.Add([ordered]@{ behavior_id = [string]$card.behavior_id; card_path = $relativeCard; source_count = $sources.Count; sources = @($sources); dropped_calls = @(); generated_narrative_is_non_authoritative = $true; synced_at = [DateTime]::UtcNow.ToString('o') })
}
$manifest = [ordered]@{ schema_version = 1; handbook_id = [string]$index.handbook_id; source_of_truth = 'real_files'; cards = @($entries); execution_authority = $false; created_at = [DateTime]::UtcNow.ToString('o') }
New-Item -ItemType Directory -Path $manifestRoot -Force | Out-Null
$path = Join-Path $manifestRoot ('sync-' + [Guid]::NewGuid().ToString('n') + '.json')
[IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
if ($PassThru) { $manifest | ConvertTo-Json -Depth 12 } else { Write-Output ('Handbook sync manifest written: ' + $path) }
