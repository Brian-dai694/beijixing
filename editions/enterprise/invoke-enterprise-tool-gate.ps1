param(
  [Parameter(Mandatory = $true)][string]$PassportPath,
  [Parameter(Mandatory = $true)][ValidateSet('sandbox', 'canary', 'internal', 'production')][string]$Environment,
  [Parameter(Mandatory = $true)][ValidateSet('read', 'write', 'external_write', 'admin')][string]$Operation,
  [Parameter(Mandatory = $true)][string]$TenantId,
  [Parameter(Mandatory = $true)][string]$OrganizationId,
  [Parameter(Mandatory = $true)][string]$ProjectId,
  [Parameter(Mandatory = $true)][string]$RoleId,
  [Parameter(Mandatory = $true)][string]$DataScopeRef,
  [Parameter(Mandatory = $true)][string]$PolicyRef,
  [Parameter(Mandatory = $true)][string]$DecisionReason,
  [Parameter(Mandatory = $true)][string]$AgentId,
  [Parameter(Mandatory = $true)][string]$TaskId,
  [Parameter(Mandatory = $true)][string]$GrantId,
  [Parameter(Mandatory = $true)][double]$EstimatedCost,
  [Parameter(Mandatory = $true)][int]$CallsUsed,
  [Parameter(Mandatory = $true)][int]$CallLimit,
  [Parameter(Mandatory = $true)][double]$BudgetUsed,
  [Parameter(Mandatory = $true)][double]$BudgetLimit,
  [string]$ApprovalId = '',
  [string]$SecondApprovalId = '',
  [string]$VerificationRef = '',
  [string]$ResponsibleParty = '',
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 12 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
try { $passport = Get-Content -LiteralPath ((Resolve-Path -LiteralPath $PassportPath -ErrorAction Stop).Path) -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Emit ([ordered]@{ status = 'blocked'; reason = 'tool_passport_invalid'; execution_authorized = $false; external_calls = $false }) 1 }
$reasons = [System.Collections.Generic.List[string]]::new()
function Deny([string]$Reason) { [void]$reasons.Add($Reason) }
if ([string]$passport.status -notin @('active', 'canary')) { Deny 'tool_not_released' }
if ([string]$passport.tenant_id -ne $TenantId -or [string]$passport.organization_id -ne $OrganizationId -or [string]$passport.project_id -ne $ProjectId) { Deny 'tool_scope_mismatch' }
if ([string]::IsNullOrWhiteSpace($RoleId)) { Deny 'business_role_required' }
if ([string]::IsNullOrWhiteSpace($DataScopeRef)) { Deny 'data_scope_ref_required' }
if ([string]::IsNullOrWhiteSpace($PolicyRef)) { Deny 'policy_ref_required' }
if ([string]::IsNullOrWhiteSpace($DecisionReason)) { Deny 'decision_reason_required' }
if ([string]::IsNullOrWhiteSpace($ResponsibleParty)) { Deny 'responsible_party_required' }
if ([string]$passport.tool_authority -eq 'True' -or [string]$passport.data_scope_authority -eq 'True') { Deny 'passport_cannot_grant_runtime_authority' }
if ($Environment -eq 'production' -and [string]$passport.status -ne 'active') { Deny 'production_requires_active_release' }
if ($Environment -eq 'production' -and [string]$passport.risk_level -eq 'L4' -and ($Operation -in @('write', 'external_write', 'admin'))) { if ([string]::IsNullOrWhiteSpace($ApprovalId)) { Deny 'human_approval_required' }; if ([string]::IsNullOrWhiteSpace($SecondApprovalId)) { Deny 'dual_confirmation_required' } }
if ($CallsUsed -ge $CallLimit) { Deny 'tool_call_limit_exceeded' }
if (($CallsUsed + 1) -gt [int]$passport.max_calls_per_task) { Deny 'passport_call_limit_exceeded' }
if (($BudgetUsed + $EstimatedCost) -gt $BudgetLimit) { Deny 'task_budget_exceeded' }
if ($EstimatedCost -lt 0 -or $BudgetUsed -lt 0 -or $BudgetLimit -lt 0) { Deny 'negative_cost_is_invalid' }
if ($reasons.Count) { Emit ([ordered]@{ status = 'blocked'; tool_id = [string]$passport.tool_id; reasons = @($reasons); execution_authorized = $false; external_calls = $false; process_started = $false }) 1 }
$audit = Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
$callTrace = 'tool-call-' + [Guid]::NewGuid().ToString('n')
& $audit -EventType tool_call_screened -Decision allow -TenantId $TenantId -OrganizationId $OrganizationId -UserId $AgentId -AgentId $AgentId -AgentVersion ([string]$passport.tool_version) -TaskId $TaskId -GrantId $GrantId -TraceId $callTrace -PolicyVersion '2.14.0' -PolicyRef $PolicyRef -DecisionReason $DecisionReason -DataRefs @($DataScopeRef) -VerificationRef $VerificationRef -ResponsibleParty $ResponsibleParty -ArtifactRefs @([string]$passport.artifact_ref) | Out-Null
Emit ([ordered]@{ status = 'allowed'; tool_id = [string]$passport.tool_id; role_id = $RoleId; data_scope_ref = $DataScopeRef; policy_ref = $PolicyRef; execution_authorized = $true; requires_task_grant = $true; process_started = $false; external_calls = $false; permission_expanded = $false; next_call_count = $CallsUsed + 1 })
