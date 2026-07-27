param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'obsidian-integration-policy.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$export = Join-Path $PSScriptRoot 'new-enterprise-obsidian-note.ps1'
$feedback = Join-Path $PSScriptRoot 'new-enterprise-obsidian-feedback-candidate.ps1'
function Run([string]$Script, [string[]]$Arguments) { $raw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1); [pscustomobject]@{ code = $LASTEXITCODE; text = (($raw | ForEach-Object { $_.ToString() }) -join "`n") } }
$cases = [System.Collections.Generic.List[object]]::new()
$suffix = [Guid]::NewGuid().ToString('n')
$note = Run $export @('-TenantId','tenant_1','-OrganizationId','org_1','-ProjectId',('project_'+$suffix),'-TaskId','task_1','-GrantId','grant_obsidian_1','-AgentId','agent_1','-RiskLevel','L2','-ApprovalStatus','approved','-DataClass','internal_sanitized','-SanitizedTaskSummary','Reviewed approved references only.','-DataScopeSummary','department aggregate, no raw customer rows','-ToolSummary','readonly-report@1.0','-RiskSummary','L2 read-only, no external write','-AuditEventId','audit_1','-EvidenceRefs','evidence://receipt-1','-PassThru')
$notePath = if ($note.code -eq 0) { ($note.text | ConvertFrom-Json).note_path } else { '' }
$noteText = if ($notePath) { Get-Content -LiteralPath $notePath -Raw -Encoding UTF8 } else { '' }
$auditPath = Join-Path $projectRoot '.qianlima/run-traces/enterprise-audit-events.jsonl'
$auditText = if (Test-Path -LiteralPath $auditPath) { Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8 } else { '' }
$cases.Add([pscustomobject]@{ name='outbound_note_is_sanitized_informational_outbox'; passed=($note.code -eq 0 -and $note.text -match 'direct_vault_sync.*false' -and $noteText -match 'source_of_truth: "northstar"' -and $noteText -match 'policy_version:' -and $noteText -match 'generated_at:' -and $noteText -match 'expires_at:' -and $noteText -match 'authority: "informational_only"' -and $auditText -match 'obsidian_note_exported') })
$secret = Run $export @('-TenantId','tenant_1','-OrganizationId','org_1','-ProjectId',('secret_'+$suffix),'-TaskId','task_2','-GrantId','grant_obsidian_2','-AgentId','agent_1','-RiskLevel','L2','-ApprovalStatus','approved','-DataClass','internal_sanitized','-SanitizedTaskSummary','api_key value','-DataScopeSummary','none','-ToolSummary','none','-RiskSummary','none','-AuditEventId','audit_2','-EvidenceRefs','evidence://receipt-2','-PassThru')
$cases.Add([pscustomobject]@{ name='secret_like_outbound_content_is_blocked'; passed=($secret.code -ne 0 -and $secret.text -match 'prohibited_material') })
$inbox = Join-Path $projectRoot '.qianlima/local-data/enterprise/obsidian-inbox'
New-Item -ItemType Directory -Path $inbox -Force | Out-Null
$source = Join-Path $inbox ('feedback-'+$suffix+'.md')
[IO.File]::WriteAllText($source,'Business suggests reviewing the threshold.',[Text.UTF8Encoding]::new($false))
$candidate = Run $feedback @('-SourceNotePath',$source,'-TenantId','tenant_1','-OrganizationId','org_1','-ProjectId','project_1','-TaskId','task_1','-GrantId','grant_obsidian_1','-SubmitterId','user_1','-FeedbackType','pending_rule_change','-FeedbackText','Review the threshold through formal approval.','-PassThru')
$auditText = if (Test-Path -LiteralPath $auditPath) { Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8 } else { '' }
$cases.Add([pscustomobject]@{ name='inbound_text_creates_candidate_without_governance_changes'; passed=($candidate.code -eq 0 -and $candidate.text -match 'permission_expanded.*false' -and $candidate.text -match 'approval_changed.*false' -and $candidate.text -match 'production_config_changed.*false' -and $auditText -match 'obsidian_feedback_candidate_created') })
$cases.Add([pscustomobject]@{ name='official_sync_limitations_are_explicit'; passed=($policy.official_sync_limitations.fine_grained_enterprise_authorization -eq $false -and $policy.official_sync_limitations.member_removal_deletes_local_history -eq $false -and $policy.hard_boundaries.direct_obsidian_sync_enabled_by_default -eq $false) })
$failed = @($cases | Where-Object { -not $_.passed })
$out = [pscustomobject]@{ passed=($failed.Count -eq 0); cases=@($cases); direct_obsidian_sync=$false; permission_expanded=$false; production_writes=$false; external_calls=$false }
if($PassThru){$out|ConvertTo-Json -Depth 10}else{$cases|Format-Table -AutoSize}
if($failed.Count){throw('Enterprise Obsidian integration regression failed: '+(($failed.name)-join', '))}
