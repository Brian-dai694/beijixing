param(
  [Parameter(Mandatory = $true)][string]$PassportPath,
  [Parameter(Mandatory = $true)][ValidateSet('static_checked', 'sandboxed', 'approved', 'canary', 'active', 'suspended', 'rolled_back', 'revoked')][string]$TargetState,
  [Parameter(Mandatory = $true)][string]$EvidenceRef,
  [Parameter(Mandatory = $true)][string]$TaskId,
  [Parameter(Mandatory = $true)][string]$GrantId,
  [Parameter(Mandatory = $true)][string]$TraceId,
  [Parameter(Mandatory = $true)][string]$ApproverId,
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'enterprise-tool-governance-policy.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 12 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
try { $full = (Resolve-Path -LiteralPath $PassportPath -ErrorAction Stop).Path; $passport = Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Emit ([ordered]@{ status = 'blocked'; reason = 'tool_passport_invalid'; state_changed = $false }) 1 }
$allowedTransitions = @{ candidate = @('static_checked'); static_checked = @('sandboxed'); sandboxed = @('approved'); approved = @('canary', 'active'); canary = @('active', 'suspended', 'rolled_back'); active = @('suspended', 'rolled_back', 'revoked'); suspended = @('canary', 'rolled_back', 'revoked'); rolled_back = @('candidate', 'revoked'); discovered = @('candidate'); revoked = @() }
$current = [string]$passport.status
if (-not $allowedTransitions.ContainsKey($current) -or @($allowedTransitions[$current]) -notcontains $TargetState) { Emit ([ordered]@{ status = 'blocked'; reason = 'invalid_tool_state_transition'; current_state = $current; target_state = $TargetState; state_changed = $false }) 1 }
if ([string]::IsNullOrWhiteSpace($EvidenceRef) -or $EvidenceRef -notmatch '^(?:[a-z][a-z0-9+.-]*://|sha256:)[^\s]+$') { Emit ([ordered]@{ status = 'blocked'; reason = 'tool_state_evidence_ref_required'; state_changed = $false }) 1 }
if ($TargetState -in @('approved', 'canary', 'active') -and ([string]$passport.generated_by_agent -eq 'True' -or [string]$passport.generated_by_agent -eq 'true') -and $TargetState -eq 'active') { Emit ([ordered]@{ status = 'blocked'; reason = 'generated_tool_cannot_directly_activate'; state_changed = $false }) 1 }
if ($TargetState -eq 'active' -and $current -notin @('approved', 'canary')) { Emit ([ordered]@{ status = 'blocked'; reason = 'approved_release_required'; state_changed = $false }) 1 }
if ($TargetState -eq 'active' -and $passport.risk_level -eq 'L4' -and [string]::IsNullOrWhiteSpace($ApproverId)) { Emit ([ordered]@{ status = 'blocked'; reason = 'dual_confirmation_required'; state_changed = $false }) 1 }
$history = [ordered]@{ from = $current; to = $TargetState; evidence_ref = $EvidenceRef; approver_id = $ApproverId; changed_at = [DateTime]::UtcNow.ToString('o') }
$passport.status = $TargetState
$passport.production_authority = ($TargetState -eq 'active')
$passport | Add-Member -NotePropertyName last_transition -NotePropertyValue $history -Force
$passport | Add-Member -NotePropertyName state_history -NotePropertyValue (@($passport.state_history) + @($history)) -Force
[IO.File]::WriteAllText($full, ($passport | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
$eventMap = @{ static_checked = 'tool_static_checked'; sandboxed = 'tool_sandboxed'; approved = 'tool_approved'; canary = 'tool_canary_started'; active = 'tool_activated'; suspended = 'tool_suspended'; rolled_back = 'tool_rolled_back'; revoked = 'tool_revoked' }
$audit = Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
& $audit -EventType $eventMap[$TargetState] -Decision $(if ($TargetState -in @('suspended', 'rolled_back', 'revoked')) { 'freeze' } else { 'accept' }) -TenantId ([string]$passport.tenant_id) -OrganizationId ([string]$passport.organization_id) -UserId $ApproverId -AgentId 'tool-governor' -AgentVersion 'tool-governance-v1' -TaskId $TaskId -GrantId $GrantId -TraceId $TraceId -PolicyVersion ([string]$policy.policy_version) -ArtifactRefs @([string]$passport.artifact_ref) -EvidenceRefs @($EvidenceRef) | Out-Null
Emit ([ordered]@{ status = $TargetState; passport_id = [string]$passport.passport_id; state_changed = $true; production_authority = [bool]$passport.production_authority; permission_expanded = $false })
