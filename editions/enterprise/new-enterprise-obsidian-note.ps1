param(
  [Parameter(Mandatory = $true)][string]$TenantId,
  [Parameter(Mandatory = $true)][string]$OrganizationId,
  [Parameter(Mandatory = $true)][string]$ProjectId,
  [Parameter(Mandatory = $true)][string]$TaskId,
  [Parameter(Mandatory = $true)][string]$GrantId,
  [Parameter(Mandatory = $true)][string]$AgentId,
  [Parameter(Mandatory = $true)][ValidateSet('L1', 'L2', 'L3', 'L4')][string]$RiskLevel,
  [Parameter(Mandatory = $true)][ValidateSet('pending', 'approved', 'rejected', 'expired', 'revoked')][string]$ApprovalStatus,
  [Parameter(Mandatory = $true)][ValidateSet('public', 'internal_sanitized')][string]$DataClass,
  [Parameter(Mandatory = $true)][string]$SanitizedTaskSummary,
  [Parameter(Mandatory = $true)][string]$DataScopeSummary,
  [Parameter(Mandatory = $true)][string]$ToolSummary,
  [Parameter(Mandatory = $true)][string]$RiskSummary,
  [Parameter(Mandatory = $true)][string]$AuditEventId,
  [Parameter(Mandatory = $true)][string]$EvidenceRefs,
  [string]$OutputPath = '',
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outbox = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-obsidian/outbox')) + [IO.Path]::DirectorySeparatorChar
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 10 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
$forbidden = '(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|password|cookie|authorization:|secret_value|approval_token|private[_-]?key)'
foreach ($text in @($SanitizedTaskSummary, $DataScopeSummary, $ToolSummary, $RiskSummary, $EvidenceRefs)) { if ($text -match $forbidden) { Emit ([ordered]@{ status = 'blocked'; reason = 'obsidian_note_contains_prohibited_material'; note_written = $false }) 1 } }
if ($EvidenceRefs -notmatch '^(?:[a-z][a-z0-9+.-]*://|sha256:)[^\s]+(?:;(?:[a-z][a-z0-9+.-]*://|sha256:)[^\s]+)*$') { Emit ([ordered]@{ status = 'blocked'; reason = 'reference_only_evidence_required'; note_written = $false }) 1 }
$safe = ($ProjectId + '-' + $TaskId) -replace '[^A-Za-z0-9._-]', '_'
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $outbox ($safe + '.md') }
$full = [IO.Path]::GetFullPath($OutputPath)
if (-not $full.StartsWith($outbox, [StringComparison]::OrdinalIgnoreCase)) { Emit ([ordered]@{ status = 'blocked'; reason = 'obsidian_note_outside_governed_outbox'; note_written = $false }) 1 }
if (Test-Path -LiteralPath $full) { Emit ([ordered]@{ status = 'blocked'; reason = 'obsidian_note_already_exists'; note_written = $false }) 1 }
$generatedAt = [DateTime]::UtcNow
$expiresAt = $generatedAt.AddHours(24)
$auditLine = [string]::Concat('- audit_event_id: ', $AuditEventId)
$evidenceLine = [string]::Concat('- evidence_refs: ', $EvidenceRefs)
$lines = @(
  '---',
  ('tenant_id: "' + $TenantId + '"'),
  ('organization_id: "' + $OrganizationId + '"'),
  ('project_id: "' + $ProjectId + '"'),
  ('task_id: "' + $TaskId + '"'),
  ('grant_id: "' + $GrantId + '"'),
  ('agent_id: "' + $AgentId + '"'),
  ('risk_level: "' + $RiskLevel + '"'),
  ('approval_status: "' + $ApprovalStatus + '"'),
  'source_of_truth: "northstar"',
  ('data_class: "' + $DataClass + '"'),
  'policy_version: "2.14.0"',
  ('generated_at: "' + $generatedAt.ToString('o') + '"'),
  ('expires_at: "' + $expiresAt.ToString('o') + '"'),
  'authority: "informational_only"',
  '---',
  '',
  '# Agent Task Governance Summary',
  '',
  '## Task Execution Summary',
  '',
  $SanitizedTaskSummary,
  '',
  '## Data Access Scope',
  '',
  $DataScopeSummary,
  '',
  '## Agents and Tools',
  '',
  $ToolSummary,
  '',
  '## Risk and Approval',
  '',
  $RiskSummary,
  '',
  '## Audit and Evidence',
  '',
  $auditLine,
  $evidenceLine,
  '',
  '## Business Context (Human Input)',
  '',
  '## Business Review (Human Input)',
  '',
  '## Improvement Proposals (Candidate Only)',
  ''
)
New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
[IO.File]::WriteAllLines($full, $lines, [Text.UTF8Encoding]::new($false))
$audit = Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
& $audit -EventType obsidian_note_exported -Decision accept -TenantId $TenantId -OrganizationId $OrganizationId -UserId $AgentId -AgentId $AgentId -AgentVersion 'obsidian-export-v1' -TaskId $TaskId -GrantId $GrantId -TraceId ('obsidian-export-' + $TaskId) -PolicyVersion '2.14.0' -PolicyRef 'policy://obsidian-integration' -DecisionReason 'sanitized informational outbox only' -DataRefs @($DataClass, $DataScopeSummary) -VerificationRef $AuditEventId -ResponsibleParty $AgentId -ArtifactRefs @('obsidian-outbox://' + $safe) -EvidenceRefs @($EvidenceRefs) -PassThru | Out-Null
Emit ([ordered]@{ status = 'outbox_ready'; note_path = $full; note_written = $true; source_of_truth = 'northstar'; policy_version = '2.14.0'; generated_at = $generatedAt.ToString('o'); expires_at = $expiresAt.ToString('o'); authority = 'informational_only'; direct_vault_sync = $false; production_write = $false })
