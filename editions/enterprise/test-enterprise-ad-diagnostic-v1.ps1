param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$stamp=(Get-Date).ToString('yyyyMMddHHmmssfff');$taskId="ad-diagnostic-task-$stamp";$grantId="grant-read-ad-$stamp";$traceId="trace-ad-diagnostic-$stamp"
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'beijixing-enterprise-ad-diagnostic-v1'
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$inputPath = Join-Path $tmp 'fixture.json'
$grantPath = Join-Path $root ".qianlima\run-traces\delegation-grants\$grantId.json"
$diagnosticReceiptPath = Join-Path $root ".qianlima\run-traces\enterprise-receipts\diagnostic-$stamp.json"
$verificationReceiptPath = Join-Path $root ".qianlima\run-traces\enterprise-receipts\verification-$stamp.json"
$workOrderPath = Join-Path $root ".qianlima\run-traces\enterprise-work-orders\work-order-$stamp.json"
$fixture = [ordered]@{
  task_id=$taskId; data_scope='advertising'; as_of='2026-07-25'
  rows=@(
    [ordered]@{campaign_id='campaign-high-acos';target_id='target-1';spend=120;sales=80;acos=1.5;cpc=2.4;budget=150},
    [ordered]@{campaign_id='campaign-healthy';target_id='target-2';spend=20;sales=100;acos=0.2;cpc=0.5;budget=100}
  )
}
$fixture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $inputPath -Encoding UTF8
$issuer = Join-Path $PSScriptRoot 'new-enterprise-ad-diagnostic-v1-grant.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $issuer -GrantId $grantId -TaskId $taskId -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId $traceId -AttestationStatus verified -OutputPath $grantPath -PassThru | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Diagnostic Grant fixture issuance failed.' }
$broker = Join-Path $PSScriptRoot 'invoke-enterprise-ad-diagnostic-v1-broker.ps1'
$brokerRaw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $broker -InputPath $inputPath -GrantPath $grantPath -TenantId tenant-1 -OrganizationId org-1 -EmployeeId employee-1 -DeviceId device-1 -ProjectId project-1 -CostCenter ads-1 -AgentId ad-readonly-agent -AgentVersion ad-diagnostic-v1 -TraceId $traceId -AgentTrust T1 -AttestationStatus verified -ReceiptPath $diagnosticReceiptPath -PassThru)
if ($LASTEXITCODE -ne 0) { throw 'Diagnostic Broker fixture unexpectedly failed.' }
$brokerResult = ($brokerRaw -join "`n") | ConvertFrom-Json
$verifier = Join-Path $PSScriptRoot 'verify-enterprise-ad-diagnostic-v1-receipt.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifier -ReceiptPath $diagnosticReceiptPath -SourcePath $inputPath -VerifierId independent-verifier -ExpectedTaskId $taskId -ExpectedGrantId $grantId -VerificationReceiptPath $verificationReceiptPath -PassThru | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Diagnostic verification fixture unexpectedly failed.' }
$script = Join-Path $PSScriptRoot 'invoke-enterprise-ad-diagnostic-v1.ps1'
$raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -InputPath $inputPath -GrantPath $grantPath -ExpectedTaskId $taskId -PassThru
if ($LASTEXITCODE -ne 0) { throw 'Diagnostic fixture unexpectedly failed.' }
$packPath = Join-Path $tmp 'diagnostic-pack.json'
$raw | Set-Content -LiteralPath $packPath -Encoding UTF8
$result = $raw | ConvertFrom-Json
$workOrderScript = Join-Path $PSScriptRoot 'new-enterprise-ad-diagnostic-v1-work-order.ps1'
$workOrderRaw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workOrderScript -DiagnosticPackPath $packPath -GrantPath $grantPath -DiagnosticReceiptPath $diagnosticReceiptPath -VerificationReceiptPath $verificationReceiptPath -RequesterId 'employee-1' -ApproverId 'manager-1' -ConfirmationId 'approval-1' -TenantId 'tenant-1' -OrganizationId 'org-1' -EmployeeId 'employee-1' -DeviceId 'device-1' -ProjectId 'project-1' -CostCenter 'ads-1' -VerifierId 'independent-verifier' -ApproverRole 'department_manager' -BeforeBid 1.25 -BeforeBudget 150 -OutputPath $workOrderPath -Confirmed -PassThru 2>&1)
if ($LASTEXITCODE -ne 0) { throw ('Approved work-order preview unexpectedly failed: ' + ($workOrderRaw -join "`n")) }
$workOrder = $workOrderRaw | ConvertFrom-Json
$persistedWorkOrder = Get-Content -LiteralPath $workOrderPath -Raw -Encoding UTF8|ConvertFrom-Json
$auditPath=Join-Path $root '.qianlima\run-traces\enterprise-audit-events.jsonl'
$workOrderAudit=@(Get-Content -LiteralPath $auditPath -Encoding UTF8|ForEach-Object{if(-not[string]::IsNullOrWhiteSpace($_)){$_|ConvertFrom-Json}}|Where-Object{$_.event_type-eq'artifact_received'-and$_.work_order_ref-eq('work-order:'+$workOrder.work_order_id)}|Select-Object -Last 1)
$duplicateWorkOrderRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workOrderScript -DiagnosticPackPath $packPath -GrantPath $grantPath -DiagnosticReceiptPath $diagnosticReceiptPath -VerificationReceiptPath $verificationReceiptPath -RequesterId 'employee-1' -ApproverId 'manager-1' -ConfirmationId 'approval-duplicate' -TenantId 'tenant-1' -OrganizationId 'org-1' -EmployeeId 'employee-1' -DeviceId 'device-1' -ProjectId 'project-1' -CostCenter 'ads-1' -VerifierId 'independent-verifier' -ApproverRole 'department_manager' -BeforeBid 1.25 -BeforeBudget 150 -OutputPath $workOrderPath -Confirmed -PassThru 2>&1)
$duplicateWorkOrderCode=$LASTEXITCODE
$forgedPackPath = Join-Path $tmp "forged-pack-$stamp.json"
$forgedPack = $result | ConvertTo-Json -Depth 15 | ConvertFrom-Json
$forgedPack.action_cards[0].recommendation = 'forged_action'
$forgedPack | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $forgedPackPath -Encoding UTF8
$forgedWorkOrderRaw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workOrderScript -DiagnosticPackPath $forgedPackPath -GrantPath $grantPath -DiagnosticReceiptPath $diagnosticReceiptPath -VerificationReceiptPath $verificationReceiptPath -RequesterId 'employee-1' -ApproverId 'manager-1' -ConfirmationId 'approval-forged' -TenantId 'tenant-1' -OrganizationId 'org-1' -EmployeeId 'employee-1' -DeviceId 'device-1' -ProjectId 'project-1' -CostCenter 'ads-1' -VerifierId 'independent-verifier' -ApproverRole 'department_manager' -BeforeBid 1.25 -BeforeBudget 150 -Confirmed -PassThru 2>&1)
$forgedWorkOrderCode = $LASTEXITCODE
$mismatchedVerifierRaw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workOrderScript -DiagnosticPackPath $packPath -GrantPath $grantPath -DiagnosticReceiptPath $diagnosticReceiptPath -VerificationReceiptPath $verificationReceiptPath -RequesterId 'employee-1' -ApproverId 'manager-1' -ConfirmationId 'approval-wrong-verifier' -TenantId 'tenant-1' -OrganizationId 'org-1' -EmployeeId 'employee-1' -DeviceId 'device-1' -ProjectId 'project-1' -CostCenter 'ads-1' -VerifierId 'spoofed-verifier' -ApproverRole 'department_manager' -BeforeBid 1.25 -BeforeBudget 150 -Confirmed -PassThru 2>&1)
$mismatchedVerifierCode = $LASTEXITCODE
$revoker = Join-Path $PSScriptRoot 'revoke-enterprise-grant.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $revoker -GrantPath $grantPath -ActorId platform-admin-test -Reason 'work_order_revocation_regression' -PassThru | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Work Order Grant revocation fixture failed.' }
$revokedWorkOrderRaw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workOrderScript -DiagnosticPackPath $packPath -GrantPath $grantPath -DiagnosticReceiptPath $diagnosticReceiptPath -VerificationReceiptPath $verificationReceiptPath -RequesterId 'employee-1' -ApproverId 'manager-1' -ConfirmationId 'approval-revoked' -TenantId 'tenant-1' -OrganizationId 'org-1' -EmployeeId 'employee-1' -DeviceId 'device-1' -ProjectId 'project-1' -CostCenter 'ads-1' -VerifierId 'independent-verifier' -ApproverRole 'department_manager' -BeforeBid 1.25 -BeforeBudget 150 -Confirmed -PassThru 2>&1)
$revokedWorkOrderCode = $LASTEXITCODE
$cases = @(
  [pscustomobject]@{name='anomaly_becomes_action_card';passed=($result.status -eq 'review_required' -and @($result.action_cards).Count -eq 1)},
  [pscustomobject]@{name='evidence_contains_source_hash_and_window';passed=($result.action_cards[0].evidence.source_hash -match '^[a-f0-9]{64}$' -and $result.action_cards[0].evidence.data_as_of -eq '2026-07-25')},
  [pscustomobject]@{name='write_is_never_ready';passed=($result.dispatch_ready -eq $false -and $result.write_performed -eq $false -and $result.approval_required -eq $true)},
  [pscustomobject]@{name='rollback_and_readback_are_declared';passed=($result.action_cards[0].rollback -eq 'restore_approved_before_value' -and @($result.action_cards[0].verification) -contains 'day_3' -and @($result.action_cards[0].verification) -contains 'day_7')},
  [pscustomobject]@{name='external_calls_are_disabled';passed=($result.external_calls -eq $false)},
  [pscustomobject]@{name='approved_work_order_remains_non_executing';passed=($workOrder.status -eq 'approved_preview' -and $workOrder.execution_authorized -eq $false -and $workOrder.write_performed -eq $false -and $workOrder.requester_id -ne $workOrder.approver_id)},
  [pscustomobject]@{name='approved_work_order_has_snapshot_and_rollback';passed=($workOrder.before_snapshot.bid -eq 1.25 -and $workOrder.rollback.budget -eq 150 -and @($workOrder.post_change_verification) -contains 'day_7')},
  [pscustomobject]@{name='approved_work_order_is_persisted_once';passed=((Test-Path -LiteralPath $workOrderPath)-and$persistedWorkOrder.work_order_id-eq$workOrder.work_order_id-and$persistedWorkOrder.execution_authorized-eq$false)},
  [pscustomobject]@{name='approved_work_order_cannot_be_overwritten';passed=($duplicateWorkOrderCode-ne0-and(($duplicateWorkOrderRaw-join"`n")-match'work_order_already_exists')-and(Get-Content -LiteralPath $workOrderPath -Raw -Encoding UTF8|ConvertFrom-Json).work_order_id-eq$workOrder.work_order_id)},
  [pscustomobject]@{name='approved_work_order_has_audit_lineage';passed=(@($workOrderAudit).Count-eq1-and$workOrderAudit[0].decision-eq'accept'-and$workOrderAudit[0].grant_id-eq$grantId-and@($workOrderAudit[0].evidence_refs).Count-eq3)},
  [pscustomobject]@{name='approved_preview_has_verified_evidence_receipt';passed=($workOrder.evidence_receipt.receipt_type -eq 'approval_preview' -and $workOrder.evidence_receipt.verification_status -eq 'passed' -and $workOrder.evidence_receipt.verifier_id -eq 'independent-verifier' -and $workOrder.evidence_receipt.integrity_hash -match '^sha256:[a-f0-9]{64}$' -and $workOrder.diagnostic_receipt_ref -eq ('receipt:' + $brokerResult.receipt.receipt_id) -and $workOrder.verification_receipt_ref -eq ('verification:' + (Get-Content -LiteralPath $verificationReceiptPath -Raw -Encoding UTF8|ConvertFrom-Json).receipt_id) -and @($workOrder.evidence_receipt.uncertainties) -contains 'real_runner_disabled')}
  [pscustomobject]@{name='tampered_action_card_blocked';passed=($forgedWorkOrderCode -ne 0 -and (($forgedWorkOrderRaw -join "`n") -match 'diagnostic_result_hash_mismatch'))}
  [pscustomobject]@{name='spoofed_verifier_blocked';passed=($mismatchedVerifierCode -ne 0 -and (($mismatchedVerifierRaw -join "`n") -match 'verifier_identity_mismatch'))}
  [pscustomobject]@{name='revoked_grant_blocked_before_work_order';passed=($revokedWorkOrderCode -ne 0 -and (($revokedWorkOrderRaw -join "`n") -match 'grant_revoked'))}
)
$failed=@($cases | Where-Object { -not $_.passed }); $out=[pscustomobject]@{passed=($failed.Count -eq 0);cases=$cases;external_calls=$false;write_performed=$false}; if($PassThru){$out|ConvertTo-Json -Depth 10}else{$cases|Format-Table -AutoSize}; if($failed.Count){throw('Enterprise ad diagnostic regression failed: '+(($failed.name)-join ', '))}
