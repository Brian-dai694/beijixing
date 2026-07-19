<#
.SYNOPSIS
  Build the owner-facing P0 projection for one human-owned goal.
.DESCRIPTION
  This is a Broker-owned read model. It joins Work Node state with append-only
  verification/revocation events and Action Receipts. A node can be projected
  as verified only when an accepted verification event corroborates it.
#>
param(
  [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9._-]+$')] [string]$GoalId,
  [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9._-]+$')] [string]$Owner,
  [ValidatePattern('^[a-zA-Z0-9._-]+$')] [string]$ProjectionId = '',
  [string]$OutputPath = '',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$traceRoot = Join-Path $projectRoot '.qianlima\run-traces'
$projectionRoot = [IO.Path]::GetFullPath((Join-Path $traceRoot 'manager-projections')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if ([string]::IsNullOrWhiteSpace($ProjectionId)) { $ProjectionId = "projection-$GoalId-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $projectionRoot "$ProjectionId.json" }
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if (-not $outputFullPath.StartsWith($projectionRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Manager projections must remain under .qianlima/run-traces/manager-projections.' }
if (Test-Path -LiteralPath $outputFullPath) { throw "Projection already exists (immutable snapshot): $ProjectionId" }
if (-not (Test-Path -LiteralPath (Split-Path -Parent $outputFullPath) -PathType Container)) { New-Item -ItemType Directory -Path (Split-Path -Parent $outputFullPath) -Force | Out-Null }

function Read-JsonLines([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  $items = @()
  foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $items += ($line | ConvertFrom-Json) }
    catch { throw "Invalid append-only event in ${Path}: $($_.Exception.Message)" }
  }
  return @($items)
}
function Get-FileSha256([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return 'sha256:' + ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))) -replace '-','').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

$auditEvents = Read-JsonLines (Join-Path $traceRoot 'audit-events.jsonl')
$revocations = Read-JsonLines (Join-Path $traceRoot 'grant-revocations.jsonl')
$nodeRoot = Join-Path $traceRoot 'work-nodes'
$nodes = @()
if (Test-Path -LiteralPath $nodeRoot) {
  foreach ($nodeFile in @(Get-ChildItem -LiteralPath $nodeRoot -Filter '*.json' -File)) {
    $node = Get-Content -LiteralPath $nodeFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($node.goal_id -eq $GoalId) { $nodes += $node }
  }
}

$nodeViews = @()
$riskFlags = @()
$totalCost = 0.0
foreach ($node in @($nodes | Sort-Object work_node_id)) {
  $nodeId = [string]$node.work_node_id
  $grantId = [string]$node.grant_id
  $verificationEvents = @($auditEvents | Where-Object { $_.event_type -eq 'verification_completed' -and $_.task_id -eq $nodeId -and $_.grant_id -eq $grantId })
  $acceptedVerification = @($verificationEvents | Where-Object { $_.decision -eq 'accept' } | Select-Object -Last 1)
  $frozenVerification = @($verificationEvents | Where-Object { $_.decision -eq 'freeze' } | Select-Object -Last 1)
  $revoked = @($revocations | Where-Object { $_.grant_id -eq $grantId } | Select-Object -Last 1)
  $effectiveStatus = [string]$node.status
  if ($revoked.Count -gt 0 -or $frozenVerification.Count -gt 0) { $effectiveStatus = 'blocked' }
  elseif ($effectiveStatus -eq 'verified' -and $acceptedVerification.Count -eq 0) {
    $effectiveStatus = 'awaiting_verification'
    $riskFlags += [ordered]@{ kind='verification_missing_audit'; node_ref=$nodeId; detail='Node claimed verified without an accepted Broker verification event.' }
  }

  $receiptRoot = Join-Path $traceRoot "action-receipts/$nodeId"
  $receipts = @()
  if (Test-Path -LiteralPath $receiptRoot) {
    foreach ($receiptFile in @(Get-ChildItem -LiteralPath $receiptRoot -Filter '*.json' -File)) {
      $receipt = Get-Content -LiteralPath $receiptFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($receipt.work_node_id -eq $nodeId) { $receipts += $receipt }
    }
  }
  foreach ($receipt in $receipts) { if ($null -ne $receipt.cost.estimated_usd) { $totalCost += [double]$receipt.cost.estimated_usd } }
  $latestReceipt = @($receipts | Sort-Object { [int]$_.sequence } | Select-Object -Last 1)
  $testRef = [string]$node.acceptance_criteria.test_result_ref
  $testHash = if ($testRef) { Get-FileSha256 (Join-Path $projectRoot $testRef) } else { $null }
  $verificationRef = if ($acceptedVerification.Count -gt 0) { $acceptedVerification[0] } elseif ($frozenVerification.Count -gt 0) { $frozenVerification[0] } else { $null }
  $diffRef = if ($null -ne $verificationRef -and @($verificationRef.data_refs).Count -gt 0) { [string]$verificationRef.data_refs[0] } else { $null }
  $effectiveEvidenceHash = if ($latestReceipt.Count -gt 0 -and $latestReceipt[0].output_hash) { [string]$latestReceipt[0].output_hash } else { $testHash }

  $projectedVerifiedAt = if ($effectiveStatus -eq 'verified') { $node.verified_at } else { $null }
  $nodeBlocker = $null
  if ($effectiveStatus -eq 'blocked') {
    $detail = if ($null -ne $revoked) { "Grant revoked: $($revoked.reason)" } elseif ($null -ne $frozenVerification) { [string]$frozenVerification[0].reason } else { 'Broker blocked this node.' }
    $riskFlags += [ordered]@{ kind='verification_failed'; node_ref=$nodeId; detail=$detail }
    $nodeBlocker = $detail
  }
  $nodeViews += [ordered]@{
    work_node_id=$nodeId; milestone=[string]$node.milestone; status=$effectiveStatus; verified_at=$projectedVerifiedAt
    risk_ceiling=[string]$node.risk_ceiling; blocker=$nodeBlocker
    traceability=[ordered]@{ diff_ref=$diffRef; test_result_ref=$testRef; evidence_hash=$effectiveEvidenceHash; policy_version=[string]$node.acceptance_criteria.policy_hash; action_receipt_count=$receipts.Count }
  }
}

$verifiedCount = @($nodeViews | Where-Object { $_.status -eq 'verified' }).Count
$blockedCount = @($nodeViews | Where-Object { $_.status -eq 'blocked' }).Count
$inProgressCount = @($nodeViews | Where-Object { $_.status -in @('granted','running','awaiting_verification') }).Count
$totalCount = $nodeViews.Count
$percentVerified = if ($totalCount -eq 0) { 0 } else { [math]::Round((100 * $verifiedCount / $totalCount), 1) }
$costPerVerified = if ($verifiedCount -gt 0) { [math]::Round($totalCost / $verifiedCount, 6) } else { $null }
$blockedSummary = if ($blockedCount -gt 0) { "$blockedCount Work Node(s) are blocked and require resolution before progress can continue." } else { 'No Work Nodes are currently blocked.' }
$inProgressSummary = if ($inProgressCount -gt 0) { "$inProgressCount Work Node(s) remain in governed execution or verification." } else { 'No Work Nodes are awaiting execution or verification.' }
$summary = @(
  "Goal $GoalId has $verifiedCount of $totalCount Work Nodes independently verified ($percentVerified%).",
  $blockedSummary,
  $inProgressSummary,
  'No owner decision is pending in this P0 projection.'
) -join ' '
$verifiedOutcomes = @($nodeViews | Where-Object { $_.status -eq 'verified' } | ForEach-Object { [ordered]@{ work_node_id=$_.work_node_id; milestone=$_.milestone; verified_at=$_.verified_at; evidence_hash=$_.traceability.evidence_hash } })
$blockers = @($nodeViews | Where-Object { $_.status -eq 'blocked' } | ForEach-Object { [ordered]@{ work_node_id=$_.work_node_id; reason=$_.blocker; evidence_ref=$_.traceability.diff_ref } })
$evidenceRefs = @($nodeViews | ForEach-Object { if ($_.traceability.evidence_hash) { [ordered]@{ work_node_id=$_.work_node_id; evidence_hash=$_.traceability.evidence_hash; diff_ref=$_.traceability.diff_ref; test_result_ref=$_.traceability.test_result_ref } } })

$projection = [ordered]@{
  schema_version=1; projection_type='qianlima_manager_projection'; projection_id=$ProjectionId; goal_id=$GoalId; owner=$Owner
  generated_at=(Get-Date).ToUniversalTime().ToString('o')
  goal_progress=[ordered]@{ total_nodes=$totalCount; verified=$verifiedCount; blocked=$blockedCount; in_progress=$inProgressCount; percent_verified=$percentVerified }
  nodes=@($nodeViews)
  cost=[ordered]@{ cost_to_date_usd=[math]::Round($totalCost, 6); cost_per_verified_node_usd=$costPerVerified; note='Includes allowed, denied, frozen, and retry action receipts.' }
  verified_outcomes=@($verifiedOutcomes); blockers=@($blockers); decision_requests=@(); pending_decisions=@(); cost_status='not_evaluated_against_goal_budget'; evidence_refs=@($evidenceRefs)
  risk_flags=@($riskFlags); human_readable_summary=$summary
}
[IO.File]::WriteAllText($outputFullPath, ($projection | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'write-audit-event.ps1') -EventType 'manager_projection_published' -Decision allow `
  -TaskId $GoalId -Reason "Manager projection published: $ProjectionId" -DataRef @("run-traces/manager-projections/$ProjectionId.json") | Out-Null
if ($PassThru) { [PSCustomObject]$projection } else { Write-Host "Manager projection written: $outputFullPath" }
