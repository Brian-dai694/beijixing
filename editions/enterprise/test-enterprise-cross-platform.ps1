<##
.SYNOPSIS
  Exercises the Enterprise production child-call chain on Windows, macOS, or Linux.
.DESCRIPTION
  Uses the resolved PowerShell runtime to issue a Grant, run the read-only Broker,
  revoke a second Grant, and prove that the revoked Grant is blocked. No Docker,
  network listener, Provider, MCP server, or business write is used.
##>
param([switch]$PassThru)

$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'resolve-enterprise-powershell.ps1')
$runtime=Get-EnterprisePowerShellCommand
$runtimeName=[IO.Path]::GetFileNameWithoutExtension($runtime).ToLowerInvariant()
$stamp=(Get-Date).ToString('yyyyMMddHHmmssfff')
$issuer=Join-Path $PSScriptRoot 'new-enterprise-ad-diagnostic-v1-grant.ps1';$broker=Join-Path $PSScriptRoot 'invoke-enterprise-ad-diagnostic-v1-broker.ps1';$revoker=Join-Path $PSScriptRoot 'revoke-enterprise-grant.ps1'
$tmp=Join-Path ([IO.Path]::GetTempPath()) "beijixing-enterprise-cross-platform-$stamp";New-Item -ItemType Directory -Path $tmp -Force|Out-Null
function Invoke-Child([string]$Script,[string[]]$Arguments){$raw=@(& $runtime -NoProfile -File $Script @Arguments 2>&1);[pscustomobject]@{code=$LASTEXITCODE;text=(($raw|ForEach-Object{$_.ToString()})-join"`n")}}
function New-Grant([string]$Suffix){$grantId="grant-cross-$Suffix-$stamp";$taskId="task-cross-$Suffix-$stamp";$traceId="trace-cross-$Suffix-$stamp";$path=Join-Path $projectRoot ".qianlima/run-traces/delegation-grants/$grantId.json";$result=Invoke-Child $issuer @('-GrantId',$grantId,'-TaskId',$taskId,'-TenantId','tenant-cross','-OrganizationId','org-cross','-EmployeeId','employee-cross','-DeviceId','device-cross','-ProjectId','project-cross','-CostCenter','cost-cross','-AgentId','ad-readonly-agent','-AgentVersion','ad-diagnostic-v1','-TraceId',$traceId,'-AttestationStatus','verified','-OutputPath',$path,'-PassThru');if($result.code-ne 0){throw "Cross-platform Grant issuance failed: $($result.text)"};[pscustomobject]@{grant_id=$grantId;task_id=$taskId;trace_id=$traceId;path=$path}}
$active=New-Grant 'active';$sourcePath=Join-Path $tmp 'source.json';$source=[ordered]@{task_id=$active.task_id;data_scope='advertising';as_of='2026-07-25';rows=@([ordered]@{campaign_id='campaign-cross';target_id='target-cross';spend=100;sales=50;acos=1.2;cpc=2;budget=120})};[IO.File]::WriteAllText($sourcePath,($source|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$brokerResult=Invoke-Child $broker @('-InputPath',$sourcePath,'-GrantPath',$active.path,'-TenantId','tenant-cross','-OrganizationId','org-cross','-EmployeeId','employee-cross','-DeviceId','device-cross','-ProjectId','project-cross','-CostCenter','cost-cross','-AgentId','ad-readonly-agent','-AgentVersion','ad-diagnostic-v1','-TraceId',$active.trace_id,'-AgentTrust','T1','-AttestationStatus','verified','-PassThru');$brokerValue=$null;try{$brokerValue=$brokerResult.text|ConvertFrom-Json}catch{}
$revoked=New-Grant 'revoked';$revokeResult=Invoke-Child $revoker @('-GrantPath',$revoked.path,'-ActorId','platform-admin-cross','-Reason','cross_platform_test_complete','-PassThru');$revokedSource=Join-Path $tmp 'revoked-source.json';$source.task_id=$revoked.task_id;[IO.File]::WriteAllText($revokedSource,($source|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));$blocked=Invoke-Child $broker @('-InputPath',$revokedSource,'-GrantPath',$revoked.path,'-TenantId','tenant-cross','-OrganizationId','org-cross','-EmployeeId','employee-cross','-DeviceId','device-cross','-ProjectId','project-cross','-CostCenter','cost-cross','-AgentId','ad-readonly-agent','-AgentVersion','ad-diagnostic-v1','-TraceId',$revoked.trace_id,'-AgentTrust','T1','-AttestationStatus','verified','-PassThru')
$nonWindowsRuntimeValid=if($IsMacOS-or$IsLinux){$runtimeName-eq'pwsh'}else{$runtimeName-in@('pwsh','powershell')}
$memoryProductionScripts=@('..\..\.qianlima\scripts\invoke-memory-broker.ps1','..\..\.qianlima\scripts\get-qianlima-memory-card.ps1','..\..\.qianlima\scripts\invoke-brokered-context.ps1')|ForEach-Object{Join-Path $PSScriptRoot $_}
$memoryHardcodingAbsent=(@($memoryProductionScripts|ForEach-Object{(Get-Content -LiteralPath $_ -Raw -Encoding UTF8)-notmatch'(?i)(?<![\w-])powershell\.exe(?![\w-])'}|Where-Object{$_-eq$false}).Count-eq0)
$cases=@([pscustomobject]@{name='platform_runtime_resolved';passed=$nonWindowsRuntimeValid},[pscustomobject]@{name='cross_platform_broker_readonly_path';passed=($brokerResult.code-eq0-and$null-ne$brokerValue-and$brokerValue.external_calls-eq$false-and$brokerValue.write_performed-eq$false)},[pscustomobject]@{name='cross_platform_revocation_written';passed=($revokeResult.code-eq0-and$revokeResult.text-match'"revoked"\s*:\s*true')},[pscustomobject]@{name='cross_platform_revoked_grant_blocked';passed=($blocked.code-ne0-and$blocked.text-match'grant_revoked')},[pscustomobject]@{name='memory_production_chain_uses_resolver';passed=$memoryHardcodingAbsent})
$failed=@($cases|Where-Object{-not$_.passed});$out=[pscustomobject]@{passed=($failed.Count-eq0);platform=if($IsMacOS){'macos'}elseif($IsLinux){'linux'}else{'windows'};runtime=$runtimeName;cases=$cases;external_calls=$false;listeners_opened=$false;runner_started=$false;business_write=$false};if($PassThru){$out|ConvertTo-Json -Depth 10}else{$cases|Format-Table -AutoSize};if($failed.Count){throw('Enterprise cross-platform regression failed: '+(($failed.name)-join', '))}
