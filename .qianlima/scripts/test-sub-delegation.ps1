$ErrorActionPreference = 'Stop'
$grantScript = Join-Path $PSScriptRoot 'new-delegation-grant.ps1'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$grantRoot = Join-Path $projectRoot '.qianlima\run-traces\delegation-grants'
$stamp = (Get-Date).ToString('yyyyMMddHHmmssfff')
$agent = 'evidence_checker'
$created = New-Object System.Collections.Generic.List[string]

function New-Id([string]$suffix) { "subdel-$stamp-$suffix" }
function Grant-Path([string]$id) { Join-Path $grantRoot "$id.json" }
function Try-Grant([hashtable]$params) {
  try { & $grantScript @params -PassThru | Out-Null; return $null }
  catch { return $_.Exception.Message }
}

$cases = @()
# Parent grant that permits Broker-mediated sub-delegation.
$parentId = New-Id 'parent'
& $grantScript -GrantId $parentId -AgentId $agent -TaskId (New-Id 'ptask') -WorkOrderId (New-Id 'wo') `
  -DataRef 'a1', 'a2' -AllowedTool 'read_selected_sources', 'read_more' -RiskCeiling L3 `
  -VerifierAgentId $agent -MaxSteps 6 -MaxToolCalls 5 -ExpiresMinutes 20 -CanDelegate -PassThru | Out-Null
$created.Add((Grant-Path $parentId))

# Parent without can_delegate (should reject any child).
$noDelegateId = New-Id 'nodel'
& $grantScript -GrantId $noDelegateId -AgentId $agent -TaskId (New-Id 'ntask') -WorkOrderId (New-Id 'wo') `
  -DataRef 'a1' -AllowedTool 'read_selected_sources' -RiskCeiling L3 -VerifierAgentId $agent -PassThru | Out-Null
$created.Add((Grant-Path $noDelegateId))

# 1. Legitimate sub-delegation: strict subset, new task_id -> succeeds.
$childOkId = New-Id 'child-ok'
$err = Try-Grant @{ GrantId = $childOkId; AgentId = $agent; TaskId = (New-Id 'ctask-ok'); WorkOrderId = (New-Id 'wo'); DataRef = 'a1'; AllowedTool = 'read_selected_sources'; RiskCeiling = 'L2'; VerifierAgentId = $agent; MaxSteps = 3; MaxToolCalls = 2; ExpiresMinutes = 5; ParentGrantId = $parentId }
$created.Add((Grant-Path $childOkId))
$childOk = if (Test-Path -LiteralPath (Grant-Path $childOkId)) { Get-Content -LiteralPath (Grant-Path $childOkId) -Raw | ConvertFrom-Json } else { $null }
$cases += [PSCustomObject]@{ name = 'subset_child_succeeds'; passed = ($null -eq $err -and $null -ne $childOk -and $childOk.parent_grant_id -eq $parentId -and $childOk.can_delegate -eq $false) }

# 2. Parent without can_delegate rejects a child.
$e = Try-Grant @{ GrantId = New-Id 'c1'; AgentId = $agent; TaskId = (New-Id 't1'); WorkOrderId = (New-Id 'wo'); DataRef = 'a1'; AllowedTool = 'read_selected_sources'; RiskCeiling = 'L2'; VerifierAgentId = $agent; ParentGrantId = $noDelegateId }
$cases += [PSCustomObject]@{ name = 'no_can_delegate_rejected'; passed = ($e -match 'does not permit sub-delegation') }

# 3. Tool not in parent -> rejected.
$e = Try-Grant @{ GrantId = New-Id 'c2'; AgentId = $agent; TaskId = (New-Id 't2'); WorkOrderId = (New-Id 'wo'); DataRef = 'a1'; AllowedTool = 'write_everything'; RiskCeiling = 'L2'; VerifierAgentId = $agent; ParentGrantId = $parentId }
$cases += [PSCustomObject]@{ name = 'tool_escalation_rejected'; passed = ($e -match 'can only shrink') }

# 4. Risk above parent -> rejected.
$e = Try-Grant @{ GrantId = New-Id 'c3'; AgentId = $agent; TaskId = (New-Id 't3'); WorkOrderId = (New-Id 'wo'); DataRef = 'a1'; AllowedTool = 'read_selected_sources'; RiskCeiling = 'L4'; VerifierAgentId = $agent; ConfirmationRef = 'cref'; RollbackRef = 'rref'; ParentGrantId = $parentId }
$cases += [PSCustomObject]@{ name = 'risk_escalation_rejected'; passed = ($e -match 'exceeds the parent') }

# 5. Reusing the parent task_id -> rejected.
$parentObj = Get-Content -LiteralPath (Grant-Path $parentId) -Raw | ConvertFrom-Json
$e = Try-Grant @{ GrantId = New-Id 'c4'; AgentId = $agent; TaskId = $parentObj.task_id; WorkOrderId = (New-Id 'wo'); DataRef = 'a1'; AllowedTool = 'read_selected_sources'; RiskCeiling = 'L2'; VerifierAgentId = $agent; ParentGrantId = $parentId }
$cases += [PSCustomObject]@{ name = 'reuse_parent_task_rejected'; passed = ($e -match 'new task_id') }

# 6. Budget above parent -> rejected.
$e = Try-Grant @{ GrantId = New-Id 'c5'; AgentId = $agent; TaskId = (New-Id 't5'); WorkOrderId = (New-Id 'wo'); DataRef = 'a1'; AllowedTool = 'read_selected_sources'; RiskCeiling = 'L2'; VerifierAgentId = $agent; MaxSteps = 20; MaxToolCalls = 2; ParentGrantId = $parentId }
$cases += [PSCustomObject]@{ name = 'budget_escalation_rejected'; passed = ($e -match 'budget cannot exceed') }

foreach ($p in $created) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }

$cases | Format-Table -AutoSize
$failed = @($cases | Where-Object { -not $_.passed })
if ($failed.Count -gt 0) { throw "Sub-delegation regression failed: $($failed.name -join ', ')" }
Write-Host "Sub-delegation regression passed: $($cases.Count) cases."
