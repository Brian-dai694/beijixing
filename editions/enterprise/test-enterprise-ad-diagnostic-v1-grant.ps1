param([switch]$PassThru)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path;$stamp=(Get-Date).ToString('yyyyMMddHHmmssfff');$tmp=Join-Path ([IO.Path]::GetTempPath()) 'beijixing-enterprise-ad-grant-test';New-Item -ItemType Directory -Path $tmp -Force|Out-Null
$issuer=Join-Path $PSScriptRoot 'new-enterprise-ad-diagnostic-v1-grant.ps1';$grantId="grant-ad-issuer-$stamp";$taskId="task-ad-issuer-$stamp";$traceId="trace-ad-issuer-$stamp";$grantPath=Join-Path $projectRoot ".qianlima\run-traces\delegation-grants\$grantId.json"
$validRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $issuer -GrantId $grantId -TaskId $taskId -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId $traceId -AttestationStatus verified -OutputPath $grantPath -PassThru)
if($LASTEXITCODE-ne 0){throw 'Valid Grant issuance unexpectedly failed.'}
$valid=($validRaw-join "`n")|ConvertFrom-Json;$grant=Get-Content -LiteralPath $grantPath -Raw -Encoding UTF8|ConvertFrom-Json
$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl';$audit=@(Get-Content -LiteralPath $auditPath -Encoding UTF8|Where-Object{$_-match [regex]::Escape($traceId)}|Select-Object -Last 1|ForEach-Object{$_|ConvertFrom-Json})
$sourcePath=Join-Path $tmp "grant-issued-source-$stamp.json"
$source=[ordered]@{task_id=$taskId;data_scope='advertising';as_of='2026-07-25';rows=@([ordered]@{campaign_id='campaign-issued';target_id='target-issued';spend=100;sales=50;acos=1.2;cpc=2;budget=120})}
[IO.File]::WriteAllText($sourcePath,($source|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$broker=Join-Path $PSScriptRoot 'invoke-enterprise-ad-diagnostic-v1-broker.ps1'
$brokerRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $broker -InputPath $sourcePath -GrantPath $grantPath -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId $traceId -AgentTrust T1 -AttestationStatus verified -PassThru)
$brokerCode=$LASTEXITCODE;$brokerResult=$null;try{$brokerResult=(($brokerRaw|ForEach-Object{$_.ToString()})-join "`n")|ConvertFrom-Json}catch{}
$unknownRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $issuer -GrantId "grant-unknown-$stamp" -TaskId $taskId -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId unknown-agent -AgentVersion v0 -TraceId "trace-unknown-$stamp" -AttestationStatus verified -PassThru 2>&1);$unknownCode=$LASTEXITCODE
$attestationRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $issuer -GrantId "grant-no-attestation-$stamp" -TaskId $taskId -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId "trace-no-attestation-$stamp" -AttestationStatus missing -PassThru 2>&1);$attestationCode=$LASTEXITCODE
$cases=@(
  [pscustomobject]@{name='approved_agent_issues_l2_grant';passed=($valid.status-eq'issued' -and $grant.status-eq'issued' -and $grant.risk_ceiling-eq'L2' -and @($grant.allowed_operations)-contains'read_advertising')},
  [pscustomobject]@{name='grant_has_zero_egress_and_no_delegate';passed=($grant.network_access-eq'none' -and $grant.write_access-eq'none' -and $grant.can_delegate-eq$false -and $grant.revocable-eq$true)},
  [pscustomobject]@{name='grant_is_identity_and_task_bound';passed=($grant.tenant_id-eq'tenant-1' -and $grant.device_id-eq'device-1' -and $grant.task_id-eq$taskId -and $grant.trace_id-eq$traceId)},
  [pscustomobject]@{name='grant_issued_audit_event_written';passed=(@($audit).Count-eq 1 -and $audit[0].event_type-eq'grant_issued' -and $audit[0].decision-eq'allow')},
  [pscustomobject]@{name='issued_grant_can_drive_broker_without_inline_grant';passed=($brokerCode-eq 0 -and $null-ne$brokerResult -and $brokerResult.receipt.grant_id-eq$grantId -and $brokerResult.task_gate.status-eq'allowed')},
  [pscustomobject]@{name='unknown_agent_denied';passed=($unknownCode-ne 0 -and (($unknownRaw-join "`n")-match 'agent_not_registered'))},
  [pscustomobject]@{name='missing_attestation_denied';passed=($attestationCode-ne 0 -and (($attestationRaw-join "`n")-match 'verified_attestation_required'))}
)
$failed=@($cases|Where-Object{-not $_.passed});$out=[pscustomobject]@{passed=($failed.Count-eq 0);cases=$cases;external_calls=$false;network_opened=$false;write_performed=$false};if($PassThru){$out|ConvertTo-Json -Depth 10}else{$cases|Format-Table -AutoSize};if($failed.Count){throw('Enterprise Grant issuer regression failed: '+(($failed.name)-join ', '))}
