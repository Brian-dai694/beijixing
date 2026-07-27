param(
  [Parameter(Mandatory = $true)][string]$SourceNotePath,
  [Parameter(Mandatory = $true)][string]$TenantId,
  [Parameter(Mandatory = $true)][string]$OrganizationId,
  [Parameter(Mandatory = $true)][string]$ProjectId,
  [Parameter(Mandatory = $true)][string]$TaskId,
  [Parameter(Mandatory = $true)][string]$GrantId,
  [Parameter(Mandatory = $true)][string]$SubmitterId,
  [Parameter(Mandatory = $true)][ValidateSet('business_feedback', 'requirement', 'improvement_suggestion', 'pending_rule_change')][string]$FeedbackType,
  [Parameter(Mandatory = $true)][string]$FeedbackText,
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$inbox = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/local-data/enterprise/obsidian-inbox')) + [IO.Path]::DirectorySeparatorChar
$candidateRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-obsidian/feedback')) + [IO.Path]::DirectorySeparatorChar
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 10 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
try { $sourceFull = (Resolve-Path -LiteralPath $SourceNotePath -ErrorAction Stop).Path } catch { Emit ([ordered]@{ status = 'blocked'; reason = 'obsidian_feedback_source_missing'; candidate_written = $false }) 1 }
if (-not $sourceFull.StartsWith($inbox, [StringComparison]::OrdinalIgnoreCase)) { Emit ([ordered]@{ status = 'blocked'; reason = 'obsidian_feedback_outside_local_inbox'; candidate_written = $false }) 1 }
if ($FeedbackText -match '(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|password|cookie|authorization:|secret_value|approval_token|private[_-]?key)') { Emit ([ordered]@{ status = 'blocked'; reason = 'feedback_contains_prohibited_secret_material'; candidate_written = $false }) 1 }
$id = 'obsidian-feedback-' + [Guid]::NewGuid().ToString('n')
$candidate = [ordered]@{ schema_version = 1; candidate_id = $id; tenant_id = $TenantId; organization_id = $OrganizationId; project_id = $ProjectId; task_id = $TaskId; grant_id = $GrantId; submitter_id = $SubmitterId; feedback_type = $FeedbackType; feedback_text = $FeedbackText; source_note_hash = 'sha256:' + (Get-FileHash -LiteralPath $sourceFull -Algorithm SHA256).Hash.ToLowerInvariant(); status = 'candidate'; untrusted_business_input = $true; requires_identity_revalidation = $true; requires_policy_revalidation = $true; permission_expanded = $false; approval_changed = $false; budget_changed = $false; data_scope_changed = $false; production_config_changed = $false; created_at = [DateTime]::UtcNow.ToString('o') }
New-Item -ItemType Directory -Path $candidateRoot -Force | Out-Null
$path = Join-Path $candidateRoot ($id + '.json')
[IO.File]::WriteAllText($path, ($candidate | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
$audit = Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
& $audit -EventType obsidian_feedback_candidate_created -Decision accept -TenantId $TenantId -OrganizationId $OrganizationId -UserId $SubmitterId -AgentId 'obsidian-feedback-gateway' -AgentVersion 'obsidian-feedback-v1' -TaskId $TaskId -GrantId $GrantId -TraceId $id -PolicyVersion '2.14.0' -PolicyRef 'policy://obsidian-integration' -DecisionReason 'untrusted feedback candidate; revalidation required' -DataRefs @('internal_sanitized') -ResponsibleParty $SubmitterId -ArtifactRefs @('obsidian-feedback://' + $id) -EvidenceRefs @($candidate.source_note_hash) -PassThru | Out-Null
Emit ([ordered]@{ status = 'candidate'; candidate_id = $id; candidate_path = $path; permission_expanded = $false; approval_changed = $false; budget_changed = $false; data_scope_changed = $false; production_config_changed = $false })
