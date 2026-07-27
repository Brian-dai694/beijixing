param(
  [Parameter(Mandatory = $true)][string]$ToolId,
  [Parameter(Mandatory = $true)][string]$ToolVersion,
  [Parameter(Mandatory = $true)][string]$OwnerId,
  [Parameter(Mandatory = $true)][string]$TenantId,
  [Parameter(Mandatory = $true)][string]$OrganizationId,
  [Parameter(Mandatory = $true)][string]$ProjectId,
  [Parameter(Mandatory = $true)][string]$Purpose,
  [Parameter(Mandatory = $true)][string]$ApplicableScenarios,
  [Parameter(Mandatory = $true)][string]$InputSchemaRef,
  [Parameter(Mandatory = $true)][string]$OutputSchemaRef,
  [Parameter(Mandatory = $true)][string]$CapabilityBoundary,
  [Parameter(Mandatory = $true)][string]$AccessPermissions,
  [Parameter(Mandatory = $true)][ValidateSet('public', 'internal_sanitized', 'confidential_reference_only')][string]$DataClass,
  [Parameter(Mandatory = $true)][string]$DeclaredDependencies,
  [Parameter(Mandatory = $true)][ValidateSet('L1', 'L2', 'L3', 'L4')][string]$RiskLevel,
  [Parameter(Mandatory = $true)][string]$CostModel,
  [Parameter(Mandatory = $true)][string]$AuditRequirements,
  [Parameter(Mandatory = $true)][string]$RollbackRef,
  [Parameter(Mandatory = $true)][string]$ArtifactRef,
  [Parameter(Mandatory = $true)][ValidatePattern('^sha256:[a-fA-F0-9]{64}$')][string]$IntegrityHash,
  [Parameter(Mandatory = $true)][string]$TaskId,
  [Parameter(Mandatory = $true)][string]$GrantId,
  [Parameter(Mandatory = $true)][string]$TraceId,
  [string]$OutputPath = '',
  [switch]$GeneratedByAgent,
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$root = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-tools/registry')) + [IO.Path]::DirectorySeparatorChar
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 12 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
$refPattern = '^(?:[a-z][a-z0-9+.-]*://|sha256:)[^\s]+$'
if ($ArtifactRef -notmatch $refPattern -or $InputSchemaRef -notmatch $refPattern -or $OutputSchemaRef -notmatch $refPattern -or $RollbackRef -notmatch $refPattern) { Emit ([ordered]@{ status = 'blocked'; reason = 'reference_only_tool_metadata_required'; registry_written = $false }) 1 }
if ([string]::IsNullOrWhiteSpace($ApplicableScenarios) -or [string]::IsNullOrWhiteSpace($CapabilityBoundary) -or [string]::IsNullOrWhiteSpace($AccessPermissions) -or [string]::IsNullOrWhiteSpace($CostModel) -or [string]::IsNullOrWhiteSpace($AuditRequirements)) { Emit ([ordered]@{ status = 'blocked'; reason = 'tool_passport_operating_metadata_required'; registry_written = $false }) 1 }
$releaseId = $ToolId + '@' + $ToolVersion
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $safe = $releaseId -replace '[^A-Za-z0-9._-]', '_'; $OutputPath = Join-Path $root ($safe + '.json') }
$full = [IO.Path]::GetFullPath($OutputPath)
if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { Emit ([ordered]@{ status = 'blocked'; reason = 'tool_registry_outside_governed_root'; registry_written = $false }) 1 }
if (Test-Path -LiteralPath $full) { Emit ([ordered]@{ status = 'blocked'; reason = 'tool_registration_already_exists'; registry_written = $false }) 1 }
$limits = @{ L1 = 100; L2 = 50; L3 = 20; L4 = 5 }
$tool = [ordered]@{ schema_version = 1; passport_id = $releaseId; tool_id = $ToolId; tool_version = $ToolVersion; owner_id = $OwnerId; tenant_id = $TenantId; organization_id = $OrganizationId; project_id = $ProjectId; purpose = $Purpose; applicable_scenarios = @($ApplicableScenarios -split ';' | Where-Object { $_ }); input_schema_ref = $InputSchemaRef; output_schema_ref = $OutputSchemaRef; capability_boundary = $CapabilityBoundary; access_permissions = @($AccessPermissions -split ';' | Where-Object { $_ }); data_class = $DataClass; declared_dependencies = @($DeclaredDependencies -split ';' | Where-Object { $_ }); risk_level = $RiskLevel; max_calls_per_task = $limits[$RiskLevel]; cost_model = $CostModel; audit_requirements = @($AuditRequirements -split ';' | Where-Object { $_ }); rollback_ref = $RollbackRef; artifact_ref = $ArtifactRef; integrity_hash = $IntegrityHash.ToLowerInvariant(); status = 'candidate'; generated_by_agent = [bool]$GeneratedByAgent; source_pinned = $false; production_authority = $false; tool_authority = $false; data_scope_authority = $false; created_at = [DateTime]::UtcNow.ToString('o') }
New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
[IO.File]::WriteAllText($full, ($tool | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
$audit = Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
& $audit -EventType tool_registered -Decision accept -TenantId $TenantId -OrganizationId $OrganizationId -UserId $OwnerId -AgentId 'tool-governor' -AgentVersion 'tool-governance-v1' -TaskId $TaskId -GrantId $GrantId -TraceId $TraceId -PolicyVersion '2.14.0' -DecisionReason 'candidate registration only' -ResponsibleParty $OwnerId -ArtifactRefs @($ArtifactRef) -EvidenceRefs @($IntegrityHash) | Out-Null
Emit ([ordered]@{ status = 'candidate'; passport_id = $releaseId; passport_path = $full; registry_written = $true; production_authority = $false; tool_authority = $false; data_scope_authority = $false })
