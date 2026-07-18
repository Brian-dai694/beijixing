<##
.SYNOPSIS
  Regression tests for role-layered beginner manuals.
##>
param([switch]$PassThru)
$ErrorActionPreference='Stop';$root=$PSScriptRoot;$cases=[System.Collections.Generic.List[object]]::new();function Add-Case([string]$Name,[bool]$Passed){$cases.Add([PSCustomObject]@{name=$Name;passed=$Passed})};$index=Get-Content -LiteralPath (Join-Path $root '企业版分层使用说明书.md') -Raw -Encoding UTF8;$boss=Get-Content -LiteralPath (Join-Path $root '说明书-老板.md') -Raw -Encoding UTF8;$owner=Get-Content -LiteralPath (Join-Path $root '说明书-业务负责人.md') -Raw -Encoding UTF8;$employee=Get-Content -LiteralPath (Join-Path $root '说明书-员工.md') -Raw -Encoding UTF8
Add-Case 'three_role_entrypoints' ($index-match'说明书-老板.md'-and $index-match'说明书-业务负责人.md'-and $index-match'说明书-员工.md')
Add-Case 'boss_not_burdened_with_routine_approval' ($boss-match'不需要您逐条审批'-and $boss-match'日常平台超级管理员')
Add-Case 'business_owner_mcp_scope_guidance' ($owner-match'员工、设备、Agent 版本'-and $owner-match'全部工具、全部店铺、永久有效')
Add-Case 'employee_uses_natural_language' ($employee-match'直接用自然语言'-and $employee-match'不需要输入端口、密钥')
Add-Case 'employee_direct_mcp_explained' ($employee-match'业务负责人'-and $employee-match'本机 Connector')
Add-Case 'all_roles_understand_five_views_and_levels' ($index-match'L0'-and $index-match'L4'-and $index-match'业务端'-and $index-match'处理端')
$failed=@($cases|Where-Object{-not $_.passed});$result=[PSCustomObject]@{passed=($failed.Count-eq 0);cases=@($cases);files_written=$false};if($PassThru){$result|ConvertTo-Json -Depth 8}else{$cases|Format-Table -AutoSize};if($failed.Count-gt 0){throw "Layered manual regression failed: $($failed.name-join', ')"}
