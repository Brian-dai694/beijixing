param(
  [Parameter(Mandatory = $true)][string]$BehaviorId,
  [Parameter(Mandatory = $true)][string]$ChangeSummary,
  [Parameter(Mandatory = $true)][string]$DeclaredDiffRef,
  [Parameter(Mandatory = $true)][string]$TaskId,
  [Parameter(Mandatory = $true)][string]$GrantId,
  [Parameter(Mandatory = $true)][string]$TraceId,
  [string]$OutputPath = '',
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$cardRoot = Join-Path $PSScriptRoot 'behavior-cards'
$cards = @(Get-ChildItem -LiteralPath $cardRoot -Filter '*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Where-Object { $_.behavior_id -eq $BehaviorId })
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 12 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
if ($cards.Count -ne 1) { Emit ([ordered]@{ status = 'blocked'; reason = 'behavior_card_not_unique'; plan_written = $false }) 1 }
if ($DeclaredDiffRef -notmatch '^(?:[a-z][a-z0-9+.-]*://|sha256:)[^\s]+$') { Emit ([ordered]@{ status = 'blocked'; reason = 'declared_diff_reference_required'; plan_written = $false }) 1 }
$card = $cards[0]
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceSnapshot = [System.Collections.Generic.List[object]]::new()
foreach ($ref in @($card.implementation_refs) + @($card.test_refs)) {
  $path = if ($ref -is [string]) { $ref } else { [string]$ref.path }
  $fullSource = [IO.Path]::GetFullPath((Join-Path $projectRoot ($path -replace '/', '\')))
  if (-not $fullSource.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $fullSource -PathType Leaf)) { Emit ([ordered]@{ status = 'blocked'; reason = 'handbook_source_missing_or_outside_workspace'; source_path = $path; plan_written = $false }) 1 }
  $hash = (Get-FileHash -LiteralPath $fullSource -Algorithm SHA256).Hash.ToLowerInvariant()
  $sourceSnapshot.Add([ordered]@{ path = $path; sha256 = 'sha256:' + $hash; anchor = if ($ref -is [string]) { $null } else { [string]$ref.anchor } })
}
$plan = [ordered]@{ schema_version = 1; plan_id = 'handbook-plan-' + [Guid]::NewGuid().ToString('n'); behavior_id = $BehaviorId; change_summary = $ChangeSummary; declared_diff_ref = $DeclaredDiffRef; task_id = $TaskId; grant_id = $GrantId; trace_id = $TraceId; progressive_disclosure = @('behavior', 'policy_and_roles', 'implementation_and_state', 'verification_and_rollout'); affected_tools = @($card.tool_scope); affected_data_scopes = @($card.data_scope); approval_points = @($card.approval_points); state_registers = @($card.state_registers); implementation_refs = @($card.implementation_refs); test_refs = @($card.test_refs); source_snapshot = @($sourceSnapshot); source_snapshot_algorithm = 'sha256'; source_freshness_required_before_approval = $true; execution_authority = $false; plan_only = $true; created_at = [DateTime]::UtcNow.ToString('o') }
$root = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-handbook/plans')) + [IO.Path]::DirectorySeparatorChar
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $root ($plan.plan_id + '.json') }
$full = [IO.Path]::GetFullPath($OutputPath)
if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { Emit ([ordered]@{ status = 'blocked'; reason = 'handbook_plan_outside_governed_root'; plan_written = $false }) 1 }
New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
[IO.File]::WriteAllText($full, ($plan | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
Emit ([ordered]@{ status = 'plan_ready'; plan_id = $plan.plan_id; plan_path = $full; source_count = $sourceSnapshot.Count; source_freshness_required_before_approval = $true; plan_only = $true; execution_authority = $false; requires_approval = $true })
