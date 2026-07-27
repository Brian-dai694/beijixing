param(
  [Parameter(Mandatory = $true)][string]$PassportPath,
  [Parameter(Mandatory = $true)][string]$TaskId,
  [Parameter(Mandatory = $true)][string]$GrantId,
  [Parameter(Mandatory = $true)][string]$TraceId,
  [Parameter(Mandatory = $true)][ValidateSet('unnecessary_call', 'out_of_scope_data', 'repeated_call', 'tool_noise', 'skipped_verification', 'cost_overrun', 'quality_failure', 'successful_reuse')][string]$FeedbackType,
  [Parameter(Mandatory = $true)][string]$EvidenceRef,
  [Parameter(Mandatory = $true)][string]$ProposedChange,
  [ValidateRange(0, 1)][double]$QualityScore = 0,
  [ValidateRange(0, 1)][double]$RiskScore = 0,
  [string]$OutputPath = '',
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$root = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-tools/feedback')) + [IO.Path]::DirectorySeparatorChar
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 12 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
try { $passport = Get-Content -LiteralPath ((Resolve-Path -LiteralPath $PassportPath -ErrorAction Stop).Path) -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Emit ([ordered]@{ status = 'blocked'; reason = 'tool_passport_invalid'; candidate_written = $false }) 1 }
if ([string]::IsNullOrWhiteSpace($EvidenceRef) -or $EvidenceRef -notmatch '^(?:[a-z][a-z0-9+.-]*://|sha256:)[^\s]+$') { Emit ([ordered]@{ status = 'blocked'; reason = 'feedback_evidence_ref_required'; candidate_written = $false }) 1 }
if ([string]::IsNullOrWhiteSpace($ProposedChange)) { Emit ([ordered]@{ status = 'blocked'; reason = 'feedback_change_required'; candidate_written = $false }) 1 }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $safe = ([string]$passport.passport_id + '-' + $FeedbackType + '-' + [Guid]::NewGuid().ToString('n')) -replace '[^A-Za-z0-9._-]', '_'; $OutputPath = Join-Path $root ($safe + '.json') }
$full = [IO.Path]::GetFullPath($OutputPath)
if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { Emit ([ordered]@{ status = 'blocked'; reason = 'feedback_outside_governed_root'; candidate_written = $false }) 1 }
$candidate = [ordered]@{ schema_version = 1; candidate_id = 'tool-feedback-' + [Guid]::NewGuid().ToString('n'); passport_id = [string]$passport.passport_id; tool_id = [string]$passport.tool_id; tool_version = [string]$passport.tool_version; task_id = $TaskId; grant_id = $GrantId; trace_id = $TraceId; feedback_type = $FeedbackType; evidence_ref = $EvidenceRef; proposed_change = $ProposedChange; quality_score = $QualityScore; risk_score = $RiskScore; status = 'candidate'; permission_expanded = $false; auto_published = $false; created_at = [DateTime]::UtcNow.ToString('o') }
New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
[IO.File]::WriteAllText($full, ($candidate | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
$audit = Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
& $audit -EventType tool_feedback_candidate_created -Decision accept -TenantId ([string]$passport.tenant_id) -OrganizationId ([string]$passport.organization_id) -UserId ([string]$passport.owner_id) -AgentId 'tool-evaluator' -AgentVersion 'tool-feedback-v1' -TaskId $TaskId -GrantId $GrantId -TraceId $TraceId -PolicyVersion '2.14.0' -ArtifactRefs @([string]$passport.artifact_ref) -EvidenceRefs @($EvidenceRef) | Out-Null
Emit ([ordered]@{ status = 'candidate'; candidate_id = [string]$candidate.candidate_id; candidate_path = $full; candidate_written = $true; permission_expanded = $false; auto_published = $false })
