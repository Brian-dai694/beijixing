param([switch]$PassThru)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$stamp=(Get-Date).ToString('yyyyMMddHHmmssfff');$taskId="ad-verifier-task-$stamp";$grantId="grant-ad-verifier-$stamp";$traceId="trace-ad-verifier-$stamp"
$tmp=Join-Path ([IO.Path]::GetTempPath()) 'beijixing-enterprise-ad-receipt-verifier'
New-Item -ItemType Directory -Path $tmp -Force|Out-Null
$sourcePath=Join-Path $tmp "source-$stamp.json";$receiptPath=Join-Path $projectRoot ".qianlima\run-traces\enterprise-receipts\verifier-source-receipt-$stamp.json";$verificationPath=Join-Path $projectRoot ".qianlima\run-traces\enterprise-receipts\verifier-result-$stamp.json"
$grantPath=Join-Path $projectRoot ".qianlima\run-traces\delegation-grants\$grantId.json"
$fixture=[ordered]@{task_id=$taskId;data_scope='advertising';as_of='2026-07-25';rows=@([ordered]@{campaign_id='campaign-1';target_id='target-1';spend=120;sales=80;acos=1.5;cpc=2.4;budget=150})}
[IO.File]::WriteAllText($sourcePath,($fixture|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$issuer=Join-Path $PSScriptRoot 'new-enterprise-ad-diagnostic-v1-grant.ps1';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $issuer -GrantId $grantId -TaskId $taskId -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId $traceId -AttestationStatus verified -OutputPath $grantPath -PassThru|Out-Null;if($LASTEXITCODE-ne 0){throw 'Receipt Grant fixture issuance failed.'}
$broker=Join-Path $PSScriptRoot 'invoke-enterprise-ad-diagnostic-v1-broker.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $broker -InputPath $sourcePath -GrantPath $grantPath -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId $traceId -AgentTrust T1 -AttestationStatus verified -ReceiptPath $receiptPath -PassThru|Out-Null
if($LASTEXITCODE-ne 0){throw 'Broker fixture failed.'}
$verifier=Join-Path $PSScriptRoot 'verify-enterprise-ad-diagnostic-v1-receipt.ps1'
$validRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifier -ReceiptPath $receiptPath -SourcePath $sourcePath -VerifierId independent-verifier -ExpectedTaskId $taskId -ExpectedGrantId $grantId -VerificationReceiptPath $verificationPath -PassThru)
if($LASTEXITCODE-ne 0){throw 'Valid receipt unexpectedly failed verification.'}
$valid=($validRaw-join "`n")|ConvertFrom-Json
$parentReceiptId=(Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8|ConvertFrom-Json).receipt_id
$auditPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-events.jsonl'
$verificationAudit=@(Get-Content -LiteralPath $auditPath -Encoding UTF8 -ErrorAction SilentlyContinue|Where-Object{$_-match [regex]::Escape($traceId) -and $_-match 'verification_completed'}|Select-Object -Last 1|ForEach-Object{$_|ConvertFrom-Json})
$tamperedPath=Join-Path $tmp 'tampered.json';[IO.File]::WriteAllText($tamperedPath,($fixture|ConvertTo-Json -Depth 10).Replace('120','121'),[Text.UTF8Encoding]::new($false))
$tamperedRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifier -ReceiptPath $receiptPath -SourcePath $tamperedPath -VerifierId independent-verifier -ExpectedTaskId $taskId -ExpectedGrantId $grantId -PassThru 2>&1);$tamperedCode=$LASTEXITCODE
$selfRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifier -ReceiptPath $receiptPath -SourcePath $sourcePath -VerifierId ad-readonly-agent -ExpectedTaskId $taskId -ExpectedGrantId $grantId -PassThru 2>&1);$selfCode=$LASTEXITCODE
$cases=@(
  [pscustomobject]@{name='independent_verification_passed';passed=($valid.status-eq'verified' -and $valid.verification.verification_status-eq'passed' -and $valid.verification.independent_verification-eq$true)},
  [pscustomobject]@{name='verification_receipt_persisted';passed=((Test-Path $verificationPath)-and (Get-Content $verificationPath -Raw|ConvertFrom-Json).parent_receipt_id-eq$parentReceiptId)},
  [pscustomobject]@{name='tampered_source_blocked';passed=($tamperedCode-ne 0 -and (($tamperedRaw-join "`n")-match 'source_hash_mismatch'))},
  [pscustomobject]@{name='same_agent_verifier_blocked';passed=($selfCode-ne 0 -and (($selfRaw-join "`n")-match 'independent_verifier_required'))},
  [pscustomobject]@{name='verification_has_no_execution';passed=($valid.execution_authorized-eq$false -and $valid.write_performed-eq$false -and $valid.external_calls-eq$false)},
  [pscustomobject]@{name='verification_audit_event_written';passed=(@($verificationAudit).Count-eq 1 -and $verificationAudit[0].event_type-eq'verification_completed' -and $verificationAudit[0].decision-eq'allow')}
)
$failed=@($cases|Where-Object{-not $_.passed});$out=[pscustomobject]@{passed=($failed.Count-eq 0);cases=$cases;external_calls=$false;write_performed=$false};if($PassThru){$out|ConvertTo-Json -Depth 10}else{$cases|Format-Table -AutoSize};if($failed.Count){throw('Enterprise receipt verifier regression failed: '+(($failed.name)-join ', '))}
