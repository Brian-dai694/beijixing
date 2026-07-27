param([switch]$PassThru)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$writer=Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
$outputPath=Join-Path $projectRoot '.qianlima\run-traces\enterprise-audit-writer-test.jsonl'
$validRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $writer -EventType tool_allowed -Decision allow -TenantId tenant-audit -OrganizationId org-audit -UserId user-audit -AgentId agent-audit -AgentVersion v1 -TaskId task-audit -GrantId grant-audit -TraceId trace-audit -PolicyVersion enterprise-2.17.17 -DataRefs snapshot:sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -EvidenceRefs evidence:receipt-audit -OutputPath $outputPath -PassThru)
if($LASTEXITCODE-ne 0){throw 'Valid audit event unexpectedly failed.'}
$valid=($validRaw-join "`n")|ConvertFrom-Json
$oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
$secretRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $writer -EventType tool_allowed -Decision allow -TenantId tenant-audit -OrganizationId org-audit -UserId user-audit -AgentId agent-audit -AgentVersion v1 -TaskId task-audit-secret -GrantId grant-audit -TraceId trace-audit-secret -PolicyVersion enterprise-2.17.17 -DataRefs api_key=secret-value -OutputPath $outputPath -PassThru 2>&1);$secretCode=$LASTEXITCODE
$outsideRaw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $writer -EventType tool_allowed -Decision allow -TenantId tenant-audit -OrganizationId org-audit -UserId user-audit -AgentId agent-audit -AgentVersion v1 -TaskId task-audit-outside -GrantId grant-audit -TraceId trace-audit-outside -PolicyVersion enterprise-2.17.17 -OutputPath (Join-Path $env:TEMP 'outside-audit.jsonl') -PassThru 2>&1);$outsideCode=$LASTEXITCODE
$ErrorActionPreference=$oldPreference
$written=@(Get-Content -LiteralPath $outputPath -Encoding UTF8|Where-Object{$_-match 'trace-audit'}|Select-Object -Last 1|ForEach-Object{$_|ConvertFrom-Json})
$cases=@(
  [pscustomobject]@{name='valid_event_has_required_lineage';passed=($valid.event_type-eq'tool_allowed' -and $valid.trace_id-eq'trace-audit' -and $valid.policy_version-eq'enterprise-2.17.17' -and @($valid.data_refs).Count-eq 1)},
  [pscustomobject]@{name='event_appended_as_jsonl';passed=((Test-Path $outputPath)-and @($written).Count-eq 1 -and $written[0].decision-eq'allow')},
  [pscustomobject]@{name='secret_metadata_rejected';passed=($secretCode-ne 0 -and (($secretRaw-join "`n")-match 'prohibited'))},
  [pscustomobject]@{name='outside_root_rejected';passed=($outsideCode-ne 0 -and (($outsideRaw-join "`n")-match 'under .qianlima/run-traces'))}
)
$failed=@($cases|Where-Object{-not $_.passed});$out=[pscustomobject]@{passed=($failed.Count-eq 0);cases=$cases;external_calls=$false;business_write=$false};if($PassThru){$out|ConvertTo-Json -Depth 10}else{$cases|Format-Table -AutoSize};if($failed.Count){throw('Enterprise audit event regression failed: '+(($failed.name)-join ', '))}
