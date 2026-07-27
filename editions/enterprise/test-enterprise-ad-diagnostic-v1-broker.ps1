param([switch]$PassThru)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$stamp=(Get-Date).ToString('yyyyMMddHHmmssfff');$taskId="ad-broker-task-$stamp";$grantId="grant-ad-broker-$stamp";$traceId="trace-ad-broker-$stamp"
$tmp=Join-Path ([IO.Path]::GetTempPath()) 'beijixing-enterprise-ad-diagnostic-v1-broker'
New-Item -ItemType Directory -Path $tmp -Force|Out-Null
$inputPath=Join-Path $tmp 'fixture.json'
$receiptPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-receipts\test-broker-receipt.json'
$grantPath=Join-Path $projectRoot ".qianlima\run-traces\delegation-grants\$grantId.json"
$fixture=[ordered]@{
  task_id=$taskId; data_scope='advertising'; as_of='2026-07-25'
  rows=@([ordered]@{campaign_id='campaign-1';target_id='target-1';spend=120;sales=80;acos=1.5;cpc=2.4;budget=150})
}
[IO.File]::WriteAllText($inputPath,($fixture|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$issuer=Join-Path $PSScriptRoot 'new-enterprise-ad-diagnostic-v1-grant.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $issuer -GrantId $grantId -TaskId $taskId -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId $traceId -AttestationStatus verified -OutputPath $grantPath -PassThru|Out-Null
if($LASTEXITCODE-ne 0){throw 'Broker Grant fixture issuance failed.'}
$script=Join-Path $PSScriptRoot 'invoke-enterprise-ad-diagnostic-v1-broker.ps1'
$raw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -InputPath $inputPath -GrantPath $grantPath -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId $traceId -AgentTrust T1 -AttestationStatus verified -ReceiptPath $receiptPath -PassThru)
if($LASTEXITCODE-ne 0){throw 'Enterprise Broker diagnostic unexpectedly failed.'}
$result=($raw-join "`n")|ConvertFrom-Json
$receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8|ConvertFrom-Json
$blockedRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -InputPath $inputPath -GrantPath $grantPath -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId trace-ad-broker-blocked -AgentTrust T1 -AttestationStatus missing -ReceiptPath (Join-Path $projectRoot '.qianlima\run-traces\enterprise-receipts\blocked-broker-receipt.json') -PassThru 2>&1)
$blockedCode=$LASTEXITCODE
$forgedPath=Join-Path $tmp 'forged-inline-grant.json'
$forged=[ordered]@{task_id=$taskId;data_scope='advertising';grant=[ordered]@{grant_id='forged';task_id=$taskId;status='issued';data_scope=@('advertising');allowed_operations=@('read_advertising');expires_at=[DateTime]::UtcNow.AddMinutes(10).ToString('o')};rows=$fixture.rows}
[IO.File]::WriteAllText($forgedPath,($forged|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$forgedRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -InputPath $forgedPath -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId trace-ad-broker-forged -AgentTrust T1 -AttestationStatus verified -ReceiptPath (Join-Path $projectRoot '.qianlima\run-traces\enterprise-receipts\forged-broker-receipt.json') -PassThru 2>&1)
$forgedCode=$LASTEXITCODE
$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl'
$auditEvent=@(Get-Content -LiteralPath $auditPath -Encoding UTF8 -ErrorAction SilentlyContinue|Where-Object{$_-match [regex]::Escape($traceId)}|Select-Object -Last 1|ForEach-Object{$_|ConvertFrom-Json})
$cases=@(
  [pscustomobject]@{name='l2_gate_allowed';passed=($result.task_gate.status-eq'allowed')},
  [pscustomobject]@{name='diagnostic_is_review_required';passed=($result.status-eq'review_required' -and @($result.diagnostic.action_cards).Count-eq 1)},
  [pscustomobject]@{name='receipt_is_persisted_and_sanitized';passed=((Test-Path $receiptPath)-and $receipt.raw_rows_recorded-eq $false -and $receipt.source_hash-match'^[a-f0-9]{64}$')},
  [pscustomobject]@{name='no_execution_or_external_call';passed=($result.execution_authorized-eq $false -and $result.write_performed-eq $false -and $result.external_calls-eq $false -and $result.process_started-eq $false)},
  [pscustomobject]@{name='identity_and_scope_bound';passed=($receipt.tenant_id-eq'tenant-1' -and $receipt.device_id-eq'device-1' -and $receipt.project_id-eq'project-1' -and $receipt.data_scope-eq'advertising')},
  [pscustomobject]@{name='missing_attestation_blocked';passed=($blockedCode-ne 0 -and (($blockedRaw-join "`n")-match 'enterprise_l2_gate_denied'))},
  [pscustomobject]@{name='inline_forged_grant_blocked';passed=($forgedCode-ne 0 -and (($forgedRaw-join "`n")-match 'governed_grant_path_required'))},
  [pscustomobject]@{name='append_only_audit_event_written';passed=(@($auditEvent).Count-eq 1 -and $auditEvent[0].event_type-eq'tool_allowed' -and $auditEvent[0].trace_id-eq$traceId -and $auditEvent[0].decision-eq'allow')}
)
$failed=@($cases|Where-Object{-not $_.passed})
$out=[pscustomobject]@{passed=($failed.Count-eq 0);cases=$cases;external_calls=$false;process_started=$false;write_performed=$false}
if($PassThru){$out|ConvertTo-Json -Depth 10}else{$cases|Format-Table -AutoSize}
if($failed.Count){throw('Enterprise Broker diagnostic regression failed: '+(($failed.name)-join ', '))}
