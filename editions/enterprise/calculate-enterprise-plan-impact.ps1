[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$InputPath, [switch]$PassThru)
$ErrorActionPreference = 'Stop'
function Emit($Value, [int]$Code = 0) { if ($PassThru) { $Value | ConvertTo-Json -Depth 14 } else { $Value | Format-List }; if ($Code -ne 0) { exit $Code } }
function Qty($Value, [string]$Name) { if ($null -eq $Value) { throw "alignment_missing_$Name" }; $n = [decimal]$Value; if ($n -lt 0) { throw "alignment_negative_$Name" }; $n }
try { $input = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Emit ([ordered]@{status='blocked';reason='alignment_input_invalid';execution_authorized=$false}) 1 }
$plan = $input.plan; foreach ($field in @('plan_id','version','owner_id','deadline','success_condition')) { if ([string]::IsNullOrWhiteSpace([string]$plan.$field)) { Emit ([ordered]@{status='blocked';reason=('alignment_plan_missing:' + $field);execution_authorized=$false}) 1 } }
try { $deadline = [DateTime]::Parse([string]$plan.deadline).Date } catch { Emit ([ordered]@{status='blocked';reason='alignment_deadline_invalid';execution_authorized=$false}) 1 }
$requirements = @($input.requirements | Where-Object { $_.plan_id -eq $plan.plan_id }); if ($requirements.Count -eq 0) { Emit ([ordered]@{status='blocked';reason='alignment_requirements_missing';execution_authorized=$false}) 1 }
$items = [System.Collections.Generic.List[object]]::new(); $exceptions = [System.Collections.Generic.List[object]]::new()
foreach ($requirement in $requirements) {
  $resourceId = [string]$requirement.resource_id; $required = Qty $requirement.required_quantity 'required_quantity'; $resource = @($input.resources | Where-Object { $_.resource_id -eq $resourceId } | Select-Object -First 1); if ($resource.Count -ne 1) { throw ('alignment_resource_missing:' + $resourceId) }; $available = Qty $resource.available_quantity 'available_quantity'
  $baseline = @($input.baseline_requirements | Where-Object { $_.resource_id -eq $resourceId } | Select-Object -First 1); $baselineQuantity = if ($baseline.Count -eq 1) { Qty $baseline.required_quantity 'baseline_required_quantity' } else { [decimal]0 }
  $onTime = [decimal]0; $late = @(); $unverified = @()
  foreach ($commitment in @($input.commitments | Where-Object { $_.resource_id -eq $resourceId })) { $quantity = Qty $commitment.committed_quantity 'committed_quantity'; $eta = [DateTime]::Parse([string]$commitment.eta).Date; $verified = ([string]$commitment.evidence_status -eq 'verified' -and @($commitment.evidence_refs).Count -gt 0); $eligible = @('confirmed','shipped') -contains [string]$commitment.status
    if (-not $verified) { $unverified += $commitment.commitment_id; continue }; if ($eligible -and $eta -le $deadline) { $onTime += $quantity } elseif ($eligible) { $late += $commitment.commitment_id }
  }
  $gap = [Math]::Max([decimal]0, $required - $available - $onTime); $delta = $required - $baselineQuantity
  $items.Add([ordered]@{requirement_id=$requirement.requirement_id;resource_id=$resourceId;responsible_role=$requirement.responsible_role;responsible_owner_id=$resource.owner_id;baseline_required_quantity=$baselineQuantity;current_required_quantity=$required;version_impact=$delta;available_quantity=$available;on_time_committed_supply=$onTime;resource_gap=$gap;late_commitment_ids=@($late);unverified_commitment_ids=@($unverified)})
  if ($gap -gt 0 -or $late.Count -gt 0 -or $unverified.Count -gt 0) { $type = if ($gap -gt 0) {'resource_gap'} elseif ($late.Count -gt 0) {'late_commitment'} else {'unverified_commitment'}; $exceptions.Add([ordered]@{exception_id=('exception-' + [Guid]::NewGuid().ToString('n'));plan_id=$plan.plan_id;resource_id=$resourceId;type=$type;impact=[ordered]@{resource_gap=$gap;version_impact=$delta;late_commitments=@($late);unverified_commitments=@($unverified)};responsible_owner_id=$resource.owner_id;decision_deadline=$deadline.AddDays(-1).ToString('yyyy-MM-dd');options=@('confirm_additional_commitment','change_provider_or_resource','accept_delay','submit_plan_adjustment');evidence_refs=@($resource.evidence_refs)}) }
}
$report = [ordered]@{status='impact_report_ready';plan_id=$plan.plan_id;plan_version=$plan.version;deadline=$deadline.ToString('yyyy-MM-dd');items=@($items);exceptions=@($exceptions);targeted_notification_owner_ids=@($exceptions | ForEach-Object {$_.responsible_owner_id} | Sort-Object -Unique);recalculation_required_on_plan_resource_or_commitment_change=$true;execution_authorized=$false;business_write_performed=$false;external_calls=$false}
Emit $report
