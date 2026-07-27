[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$GrantPath,
    [string]$OutputPath = '',
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$grantRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\delegation-grants')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
$draftRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima\run-traces\enterprise-procurement-drafts')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
function Emit([object]$Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 16 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
function Require([object]$Value, [string]$Name) { if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { throw "bundle_replenishment_missing_$Name" } }
function Number([object]$Value, [string]$Name) { if ($null -eq $Value) { throw "bundle_replenishment_missing_$Name" }; $number = [decimal]$Value; if ($number -lt 0) { throw "bundle_replenishment_negative_$Name" }; $number }

try { $grantFull = (Resolve-Path -LiteralPath $GrantPath -ErrorAction Stop).Path } catch { Emit ([ordered]@{status='blocked';reason='grant_not_found';execution_authorized=$false}) 1 }
if (-not $grantFull.StartsWith($grantRoot, [StringComparison]::OrdinalIgnoreCase)) { Emit ([ordered]@{status='blocked';reason='grant_outside_governed_root';execution_authorized=$false}) 1 }
try { $grant = Get-Content -LiteralPath $grantFull -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Emit ([ordered]@{status='blocked';reason='grant_invalid';execution_authorized=$false}) 1 }
if ([string]$grant.status -ne 'issued') { Emit ([ordered]@{status='blocked';reason='grant_not_issued';execution_authorized=$false}) 1 }
try { if ([DateTime]::Parse([string]$grant.expires_at).ToUniversalTime() -le [DateTime]::UtcNow) { Emit ([ordered]@{status='blocked';reason='grant_expired';execution_authorized=$false}) 1 } } catch { Emit ([ordered]@{status='blocked';reason='grant_expiry_invalid';execution_authorized=$false}) 1 }
foreach ($operation in @('read_bom','read_inventory','read_supplier_directory')) { if (@($grant.allowed_operations) -notcontains $operation) { Emit ([ordered]@{status='blocked';reason=('grant_operation_denied:' + $operation);execution_authorized=$false}) 1 } }
if (@($grant.allowed_tools) -notcontains 'bundle_replenishment_v1' -or @($grant.data_scope) -notcontains 'inventory_procurement') { Emit ([ordered]@{status='blocked';reason='grant_tool_or_scope_denied';execution_authorized=$false}) 1 }
try { $input = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Emit ([ordered]@{status='blocked';reason='input_invalid';execution_authorized=$false}) 1 }
$plan = $input.plan
foreach ($field in @('plan_id','bundle_sku','planned_quantity','required_available_date','owner_id','source_refs')) { Require $plan.$field $field }
if ([string]$plan.task_id -ne [string]$grant.task_id -or [string]$plan.tenant_id -ne [string]$grant.tenant_id -or [string]$plan.organization_id -ne [string]$grant.organization_id -or [string]$plan.project_id -ne [string]$grant.project_id) { Emit ([ordered]@{status='blocked';reason='plan_grant_scope_mismatch';execution_authorized=$false}) 1 }
$plannedQuantity = Number $plan.planned_quantity 'planned_quantity'; if ($plannedQuantity -le 0) { Emit ([ordered]@{status='blocked';reason='planned_quantity_must_be_positive';execution_authorized=$false}) 1 }
try { $requiredDate = [DateTime]::Parse([string]$plan.required_available_date).Date } catch { Emit ([ordered]@{status='blocked';reason='required_available_date_invalid';execution_authorized=$false}) 1 }
$bomRows = @($input.bom | Where-Object { $_.bundle_sku -eq $plan.bundle_sku }); if ($bomRows.Count -eq 0) { Emit ([ordered]@{status='blocked';reason='bom_not_found';execution_authorized=$false}) 1 }
$items = [System.Collections.Generic.List[object]]::new()
foreach ($bom in $bomRows) {
  Require $bom.component_sku 'component_sku'; $perBundle = Number $bom.quantity_per_bundle 'quantity_per_bundle'; if ($perBundle -le 0) { throw 'bundle_replenishment_quantity_per_bundle_must_be_positive' }
  $inventory = @($input.inventory | Where-Object { $_.component_sku -eq $bom.component_sku } | Select-Object -First 1); if ($inventory.Count -ne 1) { throw ('bundle_replenishment_inventory_record_missing:' + $bom.component_sku) }
  $physical = Number $inventory.physical_quantity 'physical_quantity'; $locked = Number $inventory.order_locked_quantity 'order_locked_quantity'; $reserved = Number $inventory.bundle_reserved_quantity 'bundle_reserved_quantity'; $hold = Number $inventory.quality_hold_quantity 'quality_hold_quantity'; $available = $physical - $locked - $reserved - $hold; if ($available -lt 0) { throw ('bundle_replenishment_available_inventory_negative:' + $bom.component_sku) }
  $onTimeInbound = 0; $lateInbound = [System.Collections.Generic.List[object]]::new()
  foreach ($inbound in @($input.inbound | Where-Object { $_.component_sku -eq $bom.component_sku })) {
    $quantity = Number $inbound.unallocated_quantity 'inbound_unallocated_quantity'; $eta = [DateTime]::Parse([string]$inbound.eta).Date; $counted = @('supplier_confirmed','shipped') -contains [string]$inbound.status
    if ($counted -and $eta -le $requiredDate) { $onTimeInbound += $quantity } elseif ($counted -and $eta -gt $requiredDate) { $lateInbound.Add([ordered]@{purchase_order_ref=$inbound.purchase_order_ref; eta=$eta.ToString('yyyy-MM-dd'); unallocated_quantity=$quantity}) }
  }
  $demand = $plannedQuantity * $perBundle; $shortage = [Math]::Max([decimal]0, $demand - $available - $onTimeInbound)
  $suppliers = @($input.suppliers | Where-Object { $_.component_sku -eq $bom.component_sku -and $_.status -eq 'active' } | Sort-Object @{Expression={if($_.is_preferred -eq $true){0}else{1}}}, priority | Select-Object -First 1)
  $suggested = [decimal]0; $supplierSummary = $null
  if ($shortage -gt 0 -and $suppliers.Count -eq 1) {
    $supplier = $suppliers[0]; $moq = [Math]::Max([decimal]1, (Number $supplier.moq 'moq')); $casePack = [Math]::Max([decimal]1, (Number $supplier.case_pack 'case_pack')); $suggested = [Math]::Ceiling([double]([Math]::Max($shortage, $moq) / $casePack)) * $casePack
    $supplierSummary = [ordered]@{supplier_id=$supplier.supplier_id; supplier_profile_ref=$supplier.supplier_profile_ref; product_link_ref=$supplier.product_link_ref; contact_ref=$supplier.contact_ref; wechat_ref=$supplier.wechat_ref; moq=$moq; case_pack=$casePack; last_purchase_price=$supplier.last_purchase_price; lead_time_days=$supplier.lead_time_days}
  }
  $items.Add([ordered]@{component_sku=$bom.component_sku; bom_version=$bom.bom_version; quantity_per_bundle=$perBundle; bundle_demand=$demand; available_inventory=$available; confirmed_on_time_inbound=$onTimeInbound; shortage=$shortage; suggested_order_quantity=$suggested; supplier=$supplierSummary; late_inbound_risk=@($lateInbound); purchase_required=($shortage -gt 0); supplier_confirmation_required=($shortage -gt 0); execution_authorized=$false})
}
$draftId = 'pr-draft-' + [Guid]::NewGuid().ToString('n')
$draft = [ordered]@{schema_version=1; draft_id=$draftId; status='purchase_requisition_draft'; source_plan_id=$plan.plan_id; bundle_sku=$plan.bundle_sku; planned_quantity=$plannedQuantity; required_available_date=$requiredDate.ToString('yyyy-MM-dd'); task_id=$plan.task_id; grant_id=$grant.grant_id; source_refs=@($plan.source_refs); items=@($items); recalculation_required_on_plan_or_supply_change=$true; purchase_order_created=$false; external_calls=$false; supplier_contacted=$false; erp_write_performed=$false; execution_authorized=$false; created_at=[DateTime]::UtcNow.ToString('o')}
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $draftRoot ($draftId + '.json') }; $outputFull = [IO.Path]::GetFullPath($OutputPath)
if (-not $outputFull.StartsWith($draftRoot, [StringComparison]::OrdinalIgnoreCase)) { Emit ([ordered]@{status='blocked';reason='draft_output_outside_governed_root';execution_authorized=$false}) 1 }
if (Test-Path -LiteralPath $outputFull) { Emit ([ordered]@{status='blocked';reason='draft_already_exists';execution_authorized=$false}) 1 }
New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force | Out-Null; [IO.File]::WriteAllText($outputFull, ($draft | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
$audit = Join-Path $PSScriptRoot 'append-enterprise-audit-event.ps1'; $auditEvent = & $audit -EventType artifact_received -Decision accept -TenantId $grant.tenant_id -OrganizationId $grant.organization_id -UserId $grant.employee_id -AgentId $grant.agent_id -AgentVersion $grant.agent_version -TaskId $grant.task_id -GrantId $grant.grant_id -TraceId $grant.trace_id -PolicyVersion '2.14.0' -PolicyRef 'policy://bundle-replenishment-v1' -DecisionReason 'read-only BOM inventory inbound calculation produced a purchase requisition draft' -DataRefs @('inventory_procurement') -ArtifactRefs @('purchase-requisition-draft:' + $draftId) -EvidenceRefs @($plan.source_refs) -ResponsibleParty $plan.owner_id -PassThru | ConvertFrom-Json
Emit ([ordered]@{status='draft_ready';draft=$draft;draft_path=$outputFull;audit_event_id=$auditEvent.event_id;execution_authorized=$false})
