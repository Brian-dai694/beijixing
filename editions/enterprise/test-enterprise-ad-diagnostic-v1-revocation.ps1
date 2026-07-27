param([switch]$PassThru)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$tmp=Join-Path ([IO.Path]::GetTempPath()) 'beijixing-enterprise-ad-revocation-test'
New-Item -ItemType Directory -Path $tmp -Force|Out-Null
$stamp=(Get-Date).ToString('yyyyMMddHHmmssfff')
$issuer=Join-Path $PSScriptRoot 'new-enterprise-ad-diagnostic-v1-grant.ps1'
$revoker=Join-Path $PSScriptRoot 'revoke-enterprise-grant.ps1'
$broker=Join-Path $PSScriptRoot 'invoke-enterprise-ad-diagnostic-v1-broker.ps1'
$grantId="grant-ad-revocation-$stamp";$taskId="task-ad-revocation-$stamp";$traceId="trace-ad-revocation-$stamp"
$grantPath=Join-Path $projectRoot ".qianlima\run-traces\delegation-grants\$grantId.json"
$revocationPath=Join-Path $projectRoot '.qianlima\run-traces\grant-revocations.jsonl'
$sourcePath=Join-Path $tmp "source-$stamp.json"
$source=[ordered]@{task_id=$taskId;data_scope='advertising';as_of='2026-07-25';rows=@([ordered]@{campaign_id='campaign-revocation';target_id='target-revocation';spend=100;sales=50;acos=1.2;cpc=2;budget=120})}
[IO.File]::WriteAllText($sourcePath,($source|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$issuerRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $issuer -GrantId $grantId -TaskId $taskId -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId $traceId -AttestationStatus verified -OutputPath $grantPath -PassThru)
if($LASTEXITCODE-ne 0){throw 'Grant issuance unexpectedly failed.'}
$beforeHash=(Get-FileHash -LiteralPath $grantPath -Algorithm SHA256).Hash
$revokeRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $revoker -GrantPath $grantPath -ActorId platform-admin-1 -Reason 'task_completed' -OutputPath $revocationPath -PassThru)
$revokeCode=$LASTEXITCODE;$revokeResult=(($revokeRaw|ForEach-Object{$_.ToString()})-join "`n")|ConvertFrom-Json
$afterHash=(Get-FileHash -LiteralPath $grantPath -Algorithm SHA256).Hash
$brokerRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $broker -InputPath $sourcePath -GrantPath $grantPath -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId $traceId -AgentTrust T1 -AttestationStatus verified -PassThru 2>&1)
$brokerCode=$LASTEXITCODE;$brokerText=($brokerRaw|ForEach-Object{$_.ToString()})-join "`n"
$revocation=@(Get-Content -LiteralPath $revocationPath -Encoding UTF8|ForEach-Object{try{$_|ConvertFrom-Json}catch{}}|Where-Object{$_.grant_id-eq$grantId})
$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl'
$audit=@(Get-Content -LiteralPath $auditPath -Encoding UTF8|ForEach-Object{try{$_|ConvertFrom-Json}catch{}}|Where-Object{$_.trace_id-eq$traceId-and$_.event_type-eq'grant_revoked'})
$cases=@(
  [pscustomobject]@{name='revocation_succeeds';passed=($revokeCode-eq 0-and$revokeResult.status-eq'revoked'-and$revokeResult.revoked-eq$true-and$revokeResult.execution_authorized-eq$false)},
  [pscustomobject]@{name='revocation_ledger_contains_grant';passed=(@($revocation).Count-ge 1-and$revocation[-1].grant_id-eq$grantId-and$revocation[-1].task_id-eq$taskId)},
  [pscustomobject]@{name='grant_document_is_not_mutated';passed=($beforeHash-eq$afterHash)},
  [pscustomobject]@{name='revoked_grant_blocks_broker';passed=($brokerCode-ne 0-and$brokerText-match'grant_revoked')},
  [pscustomobject]@{name='revocation_audit_event_written';passed=(@($audit).Count-ge 1-and$audit[-1].decision-eq'revoke')},
  [pscustomobject]@{name='no_external_or_business_execution';passed=($brokerText-match'execution_authorized.*false'-and$brokerText-match'external_calls.*false')}
)
$failed=@($cases|Where-Object{-not $_.passed});$out=[pscustomobject]@{passed=($failed.Count-eq 0);cases=$cases;external_calls=$false;process_started=$false;business_write=$false};if($PassThru){$out|ConvertTo-Json -Depth 10}else{$cases|Format-Table -AutoSize};if($failed.Count){throw('Enterprise Grant revocation regression failed: '+(($failed.name)-join ', '))}
