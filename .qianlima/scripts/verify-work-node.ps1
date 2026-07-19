<#
.SYNOPSIS
  Verification Gate. Broker-owned. An Agent can NEVER call this to self-complete.
.DESCRIPTION
  Checks acceptance criteria for a Work Node and, only if ALL pass, writes
  status=verified. Otherwise writes blocked (recoverable) or rejected (terminal).
  Checks: (1) grant not revoked, (2) test-result.json failed=0, (3) every diff
  file under allowed_paths, (4) receipt chain contiguous >= min, (5) records
  policy_hash + audit lineage.
#>
param(
  [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')] [string]$WorkNodeId,
  [Parameter(Mandatory)] [string]$GrantId,
  [Parameter(Mandatory)] [string]$DiffManifestPath,  # workspace-rel file: one changed path per line
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$traceRoot = Join-Path $projectRoot '.qianlima\run-traces'
$psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
$failures = New-Object System.Collections.Generic.List[string]

function Set-NodeStatus([object]$node, [string]$status, [string]$path) {
  $node.status = $status
  if ($status -eq 'verified') { $node.verified_at = (Get-Date).ToUniversalTime().ToString('o') }
  [IO.File]::WriteAllText($path, ($node | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}

$nodePath = Join-Path $traceRoot "work-nodes/$WorkNodeId.json"
if (-not (Test-Path -LiteralPath $nodePath)) { Write-Error "work node not found: $WorkNodeId"; exit 12 }
$node = Get-Content -LiteralPath $nodePath -Raw -Encoding UTF8 | ConvertFrom-Json
$ac = $node.acceptance_criteria
if ($node.grant_id -ne $GrantId) { $failures.Add("grant_not_bound_to_node:$GrantId") }

function Test-WorkspaceRelativePath([string]$PathValue) {
  return -not ([string]::IsNullOrWhiteSpace($PathValue) -or [IO.Path]::IsPathRooted($PathValue) -or $PathValue -match '(^|[\\/])\.\.([\\/]|$)')
}

# (1) the bound Grant must be issued, unexpired, scoped to this node, and not revoked.
$grantPath = Join-Path $traceRoot "delegation-grants/$GrantId.json"
if (-not (Test-Path -LiteralPath $grantPath)) { $failures.Add("grant_missing:$GrantId") }
else {
  $grant = Get-Content -LiteralPath $grantPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($grant.grant_id -ne $GrantId -or $grant.status -ne 'issued') { $failures.Add("grant_inactive:$GrantId") }
  elseif ([datetime]$grant.expires_at -le (Get-Date).ToUniversalTime()) { $failures.Add("grant_expired:$GrantId") }
  elseif ($grant.task_id -ne $WorkNodeId) { $failures.Add("grant_task_mismatch:$GrantId") }
}
$revPath = Join-Path $traceRoot 'grant-revocations.jsonl'
if ((Test-Path -LiteralPath $revPath) -and (Get-Content -LiteralPath $revPath | Where-Object { $_ -match [regex]::Escape($GrantId) })) {
  $failures.Add("grant_revoked:$GrantId")
}

# (2) tests: failed must be 0
if ($ac.tests_required) {
  if (-not (Test-WorkspaceRelativePath $ac.test_result_ref)) { $failures.Add('test_result_path_invalid') }
  else {
    $trPath = Join-Path $projectRoot $ac.test_result_ref
    if (-not (Test-Path -LiteralPath $trPath)) { $failures.Add("test_result_missing:$($ac.test_result_ref)") }
    else {
      $tr = Get-Content -LiteralPath $trPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($tr.failed -ne 0) { $failures.Add("tests_failed:$($tr.failed)") }
      if ($tr.exit_code -ne 0) { $failures.Add("test_exit_code:$($tr.exit_code)") }
    }
  }
}

# (3) diff subset of allowed_paths
if ($ac.diff_subset_of_scope) {
  if (-not (Test-WorkspaceRelativePath $DiffManifestPath)) { $failures.Add('diff_manifest_path_invalid') }
  else {
    $diffPath = Join-Path $projectRoot $DiffManifestPath
    if (-not (Test-Path -LiteralPath $diffPath)) { $failures.Add("diff_manifest_missing") }
    else {
      $changed = Get-Content -LiteralPath $diffPath | Where-Object { $_.Trim() }
      $allowed = @($node.scope.allowed_paths)
      foreach ($f in $changed) {
        if (-not (Test-WorkspaceRelativePath $f)) { $failures.Add("diff_path_invalid:$f"); continue }
        $ok = $false
        foreach ($glob in $allowed) { if ($f -like $glob) { $ok = $true; break } }
        if (-not $ok) { $failures.Add("diff_out_of_scope:$f") }
      }
    }
  }
}

# (4) receipt chain contiguous and >= min
$rcDir = Join-Path $traceRoot "action-receipts/$WorkNodeId"
$rcCount = 0
if (Test-Path -LiteralPath $rcDir) {
  $receipts = @(
    Get-ChildItem -LiteralPath $rcDir -Filter '*.json' -File | ForEach-Object {
      Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    }
  )
  $rcCount = $receipts.Count
  $sequences = @($receipts | ForEach-Object {
    if ($_.work_node_id -ne $WorkNodeId -or $_.grant_id -ne $GrantId -or $null -eq $_.sequence) {
      $failures.Add("receipt_lineage_invalid:$($_.action_id)")
    }
    [int]$_.sequence
  } | Sort-Object)
  for ($i = 0; $i -lt $sequences.Count; $i++) {
    if ($sequences[$i] -ne $i) { $failures.Add("receipt_sequence_gap_or_duplicate:$i"); break }
  }
}
if ($rcCount -lt $ac.min_action_receipts) { $failures.Add("insufficient_receipts:$rcCount<$($ac.min_action_receipts)") }

# --- Decide + write status + audit lineage ---
$status = if ($failures.Count -eq 0) { 'verified' } else { 'blocked' }
Set-NodeStatus $node $status $nodePath
$reason = if ($failures.Count -eq 0) { "verified policy=$($ac.policy_hash.Substring(0,20)) receipts=$rcCount" } else { "blocked: $($failures -join '; ')" }
$decision = if ($status -eq 'verified') { 'accept' } else { 'freeze' }
& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'write-audit-event.ps1') `
  -EventType 'verification_completed' -Decision $decision -TaskId $WorkNodeId -GrantId $GrantId -Reason $reason `
  -DataRef @($DiffManifestPath, $ac.test_result_ref) | Out-Null

Write-Host "Work Node $WorkNodeId -> $status ($reason)"
if ($status -ne 'verified') { $result = [PSCustomObject]@{ work_node_id=$WorkNodeId; status=$status; failures=$failures }; if ($PassThru) { $result }; exit 20 }
if ($PassThru) { [PSCustomObject]@{ work_node_id=$WorkNodeId; status='verified'; policy_hash=$ac.policy_hash; receipt_count=$rcCount } }
