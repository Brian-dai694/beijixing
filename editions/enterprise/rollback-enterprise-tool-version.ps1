param(
  [Parameter(Mandatory = $true)][string]$CurrentPassportPath,
  [Parameter(Mandatory = $true)][string]$PreviousPassportPath,
  [Parameter(Mandatory = $true)][string]$Reason,
  [Parameter(Mandatory = $true)][string]$TaskId,
  [Parameter(Mandatory = $true)][string]$GrantId,
  [Parameter(Mandatory = $true)][string]$TraceId,
  [Parameter(Mandatory = $true)][string]$ApproverId,
  [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outRoot = [IO.Path]::GetFullPath((Join-Path $root '.qianlima/run-traces/enterprise-tools/rollbacks')) + [IO.Path]::DirectorySeparatorChar
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 12 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
try {
  $current = Get-Content -LiteralPath ((Resolve-Path -LiteralPath $CurrentPassportPath -ErrorAction Stop).Path) -Raw -Encoding UTF8 | ConvertFrom-Json
  $previous = Get-Content -LiteralPath ((Resolve-Path -LiteralPath $PreviousPassportPath -ErrorAction Stop).Path) -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  Emit ([ordered]@{ status = 'blocked'; reason = 'passport_invalid'; rollback_written = $false }) 1
}
$scopeMismatch = ([string]$current.tool_id -ne [string]$previous.tool_id) -or ([string]$current.tenant_id -ne [string]$previous.tenant_id) -or ([string]$current.organization_id -ne [string]$previous.organization_id)
if ($scopeMismatch) { Emit ([ordered]@{ status = 'blocked'; reason = 'rollback_scope_mismatch'; rollback_written = $false }) 1 }
if ([string]$previous.status -notin @('approved', 'active')) { Emit ([ordered]@{ status = 'blocked'; reason = 'previous_release_not_rollback_ready'; rollback_written = $false }) 1 }
$current.status = 'rolled_back'
$current.production_authority = $false
$current | Add-Member -NotePropertyName rollback_reason -NotePropertyValue $Reason -Force
$current | Add-Member -NotePropertyName rollback_target -NotePropertyValue ([string]$previous.passport_id) -Force
[IO.File]::WriteAllText($CurrentPassportPath, ($current | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
$id = 'rollback-' + [Guid]::NewGuid().ToString('n')
$receipt = [ordered]@{ schema_version = 1; rollback_id = $id; from_passport = [string]$current.passport_id; to_passport = [string]$previous.passport_id; reason = $Reason; approver_id = $ApproverId; task_id = $TaskId; grant_id = $GrantId; trace_id = $TraceId; append_only = $true; created_at = [DateTime]::UtcNow.ToString('o') }
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null
$receiptPath = Join-Path $outRoot ($id + '.json')
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
$audit = Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'
& $audit -EventType tool_rolled_back -Decision freeze -TenantId ([string]$current.tenant_id) -OrganizationId ([string]$current.organization_id) -UserId $ApproverId -AgentId 'tool-governor' -AgentVersion 'tool-governance-v1' -TaskId $TaskId -GrantId $GrantId -TraceId $TraceId -PolicyVersion '2.14.0' -DecisionReason $Reason -ResponsibleParty $ApproverId -ArtifactRefs @([string]$current.artifact_ref, [string]$previous.artifact_ref) -EvidenceRefs @('tool-rollback://' + $id) | Out-Null
Emit ([ordered]@{ status = 'rolled_back'; rollback_id = $id; rollback_path = $receiptPath; target_passport = [string]$previous.passport_id; production_authority = $false; permission_expanded = $false })
