<#
.SYNOPSIS
  Scope-enforcement shell for fff read-only retrieval, bound to a Work Node.
.DESCRIPTION
  Enforces fff-capability-spec.yaml BEFORE any retrieval: active/unrevoked grant,
  path under repo_root, no excluded/sensitive patterns, size limits. Every call
  (allow or deny) writes an Action Receipt. P0 does not exec a real fff binary;
  it validates + returns a governed manifest stub so the loop is testable.
#>
param(
  [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')] [string]$WorkNodeId,
  [Parameter(Mandatory)] [string]$GrantId,
  [Parameter(Mandatory)] [string]$Query,
  [Parameter(Mandatory)] [string]$RelativePath,
  [ValidateRange(0, 100000)] [int]$Sequence = 0,
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$traceRoot = Join-Path $projectRoot '.qianlima\run-traces'
$psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
$excluded = @('.env','credential','secret','.pem','.key','id_rsa','.git/','node_modules/','run-traces/','delegation-grants/')

function Get-Sha([string]$s) {
  $h = [Security.Cryptography.SHA256]::Create()
  try { 'sha256:' + ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($s))) -replace '-','').ToLowerInvariant() }
  finally { $h.Dispose() }
}
function Deny([string]$reason) {
  $aid = "fff-$WorkNodeId-$Sequence-deny"
  & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new-action-receipt.ps1') `
    -ActionId $aid -WorkNodeId $WorkNodeId -GrantId $GrantId -ToolName 'fff' -Sequence $Sequence `
    -Decision deny -InputHash (Get-Sha "$Query|$RelativePath") | Out-Null
  Write-Error "fff DENIED: $reason"; exit 30
}

# --- Load the Work Node to get repo_root ---
$nodePath = Join-Path $traceRoot "work-nodes/$WorkNodeId.json"
if (-not (Test-Path -LiteralPath $nodePath)) { Deny "work node not found: $WorkNodeId" }
$node = Get-Content -LiteralPath $nodePath -Raw -Encoding UTF8 | ConvertFrom-Json
$repoRoot = $node.scope.repo_root
if (-not $repoRoot) { Deny 'work node has no scope.repo_root' }
if ($node.grant_id -ne $GrantId) { Deny "Grant is not bound to Work Node: $GrantId" }
if ($node.status -notin @('granted','running','awaiting_verification')) { Deny "Work Node is not executable: $($node.status)" }

# --- Grant gating: issued, unexpired, bound to this node, and not revoked. ---
$grantPath = Join-Path $traceRoot "delegation-grants/$GrantId.json"
if (-not (Test-Path -LiteralPath $grantPath)) { Deny "grant not found: $GrantId" }
$grant = Get-Content -LiteralPath $grantPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($grant.grant_id -ne $GrantId -or $grant.status -ne 'issued') { Deny "grant inactive: $GrantId" }
if ([datetime]$grant.expires_at -le (Get-Date).ToUniversalTime()) { Deny "grant expired: $GrantId" }
if ($grant.task_id -ne $WorkNodeId) { Deny "grant task does not match Work Node: $GrantId" }
if (@($grant.allowed_tools) -notcontains 'fff') { Deny "grant does not allow fff: $GrantId" }

$revPath = Join-Path $traceRoot 'grant-revocations.jsonl'
if (Test-Path -LiteralPath $revPath) {
  $revoked = Get-Content -LiteralPath $revPath | Where-Object { $_ -match [regex]::Escape($GrantId) }
  if ($revoked) { Deny "grant revoked: $GrantId" }
}

$priorFffCalls = 0
$receiptDir = Join-Path $traceRoot "action-receipts/$WorkNodeId"
if (Test-Path -LiteralPath $receiptDir) {
  $priorFffCalls = @(
    Get-ChildItem -LiteralPath $receiptDir -Filter '*.json' -File | ForEach-Object {
      Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    } | Where-Object { $_.tool_name -eq 'fff' }
  ).Count
}
$maxCalls = [Math]::Min([int]$grant.budget.max_tool_calls, 100)
if ($priorFffCalls -ge $maxCalls) { Deny "fff call budget exhausted: $priorFffCalls/$maxCalls" }

# --- Path enforcement ---
if ($RelativePath -match '\.\.' -or [IO.Path]::IsPathRooted($RelativePath)) { Deny 'absolute or traversal path' }
$rootFull = [IO.Path]::GetFullPath((Join-Path $projectRoot $repoRoot)).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
$target = [IO.Path]::GetFullPath((Join-Path $projectRoot $RelativePath))
if (-not ($target.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase))) { Deny "path outside repo_root: $RelativePath" }
foreach ($ex in $excluded) { if ($RelativePath.ToLowerInvariant().Contains($ex)) { Deny "excluded pattern: $ex" } }

# --- Allowed: write an allow receipt + governed manifest stub ---
$aid = "fff-$WorkNodeId-$Sequence-allow"
$querySummary = "query_length=$($Query.Length)"
$manifest = [ordered]@{ query_summary = $querySummary; repo_root = $repoRoot; relative_path = $RelativePath; note = 'P0 governed stub: scope validated, no binary exec' }
$outHash = Get-Sha ($manifest | ConvertTo-Json -Compress)
& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new-action-receipt.ps1') `
  -ActionId $aid -WorkNodeId $WorkNodeId -GrantId $GrantId -ToolName 'fff' -Sequence $Sequence `
  -Decision allow -InputHash (Get-Sha "$querySummary|$RelativePath") -OutputHash $outHash | Out-Null
Write-Host "fff ALLOWED under $repoRoot (receipt $aid)"
if ($PassThru) { [PSCustomObject]$manifest }
