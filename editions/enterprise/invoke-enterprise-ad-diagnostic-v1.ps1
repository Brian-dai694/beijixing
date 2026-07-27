<##
.SYNOPSIS
  Builds a read-only Amazon advertising diagnostic action-card pack.
.DESCRIPTION
  This entrypoint reads a local snapshot only. It never calls an external API,
  changes a bid or budget, or emits a write-capable Grant.
##>
param(
  [Parameter(Mandatory=$true)][string]$InputPath,
  [string]$ExpectedTaskId = '',
  [string]$GrantPath = '',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
function Emit([hashtable]$Value, [int]$Code = 0) {
  if ($PassThru) { $Value | ConvertTo-Json -Depth 12 }
  else { $Value | Format-List }
  if ($Code -ne 0) { exit $Code }
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
  Emit ([ordered]@{ status='blocked'; reason='input_not_found'; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1
}
$raw = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8
try { $input = $raw | ConvertFrom-Json } catch { Emit ([ordered]@{ status='invalid_input'; reason='invalid_json'; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1 }
$sourceHash = (Get-FileHash -LiteralPath $InputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$grantRoot = [IO.Path]::GetFullPath((Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path '.qianlima\run-traces\delegation-grants')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
if([string]::IsNullOrWhiteSpace($GrantPath)){Emit ([ordered]@{ status='blocked'; reason='governed_grant_path_required'; source_hash=$sourceHash; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1}
try { $grantFull = (Resolve-Path -LiteralPath $GrantPath -ErrorAction Stop).Path } catch { Emit ([ordered]@{ status='blocked'; reason='grant_not_found'; source_hash=$sourceHash; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1 }
if(-not $grantFull.StartsWith($grantRoot,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{ status='blocked'; reason='grant_outside_governed_root'; source_hash=$sourceHash; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1}
try { $grant = Get-Content -LiteralPath $grantFull -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Emit ([ordered]@{ status='blocked'; reason='grant_invalid'; source_hash=$sourceHash; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1 }
$now = [DateTime]::UtcNow
if ($null -eq $grant -or [string]::IsNullOrWhiteSpace([string]$grant.grant_id)) { Emit ([ordered]@{ status='blocked'; reason='grant_missing'; source_hash=$sourceHash; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1 }
if ([string]$grant.status -ne 'issued') { Emit ([ordered]@{ status='blocked'; reason='grant_not_issued'; source_hash=$sourceHash; grant_id=[string]$grant.grant_id; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1 }
if ($ExpectedTaskId -and [string]$input.task_id -ne $ExpectedTaskId) { Emit ([ordered]@{ status='blocked'; reason='task_mismatch'; source_hash=$sourceHash; grant_id=[string]$grant.grant_id; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1 }
if ([string]$grant.task_id -ne [string]$input.task_id) { Emit ([ordered]@{ status='blocked'; reason='grant_task_mismatch'; source_hash=$sourceHash; grant_id=[string]$grant.grant_id; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1 }
if (@($grant.data_scope) -notcontains [string]$input.data_scope -or @($grant.allowed_operations) -notcontains 'read_advertising') { Emit ([ordered]@{ status='blocked'; reason='scope_or_operation_denied'; source_hash=$sourceHash; grant_id=[string]$grant.grant_id; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1 }
try { if ([DateTime]::Parse([string]$grant.expires_at).ToUniversalTime() -le $now) { Emit ([ordered]@{ status='expired_grant'; reason='grant_expired'; source_hash=$sourceHash; grant_id=[string]$grant.grant_id; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1 } } catch { Emit ([ordered]@{ status='blocked'; reason='grant_expiry_invalid'; source_hash=$sourceHash; grant_id=[string]$grant.grant_id; dispatch_ready=$false; external_calls=$false; write_performed=$false }) 1 }
$cards = [System.Collections.Generic.List[object]]::new()
foreach ($row in @($input.rows)) {
  $spend = [double]$row.spend; $sales = [double]$row.sales; $acos = [double]$row.acos; $budget = [double]$row.budget
  $reasons = [System.Collections.Generic.List[string]]::new()
  if ($acos -gt 0.80) { [void]$reasons.Add('high_acos') }
  if ($sales -eq 0 -and $spend -ge 10) { [void]$reasons.Add('spend_without_sales') }
  if ($budget -gt 0 -and $spend -ge ($budget * 0.90)) { [void]$reasons.Add('budget_pressure') }
  if ($reasons.Count -eq 0) { continue }
  $recommendation = if ($reasons -contains 'spend_without_sales') { 'pause_candidate' } elseif ($reasons -contains 'high_acos') { 'decrease_bid_or_pause_candidate' } else { 'review_budget_before_change' }
  [void]$cards.Add([ordered]@{
    campaign_id=[string]$row.campaign_id; target_id=[string]$row.target_id
    issue=(@($reasons) -join ',')
    evidence=[ordered]@{ source_hash=$sourceHash; data_as_of=[string]$input.as_of; spend=$spend; sales=$sales; acos=$acos; cpc=[double]$row.cpc; budget=$budget }
    recommendation=$recommendation
    impact=[ordered]@{ budget_exposure=$budget; write_effect='none_until_human_approval' }
    permission='read_only; L4 approval required before bid_or_budget_write'
    rollback='restore_approved_before_value'
    verification=@('day_3','day_7')
  })
}
$status = if ($cards.Count -gt 0) { 'review_required' } else { 'completed_no_anomaly' }
Emit ([ordered]@{
  contract_id='beijixing-enterprise-amazon-ad-diagnostic-v1'; status=$status
  task_id=[string]$input.task_id; grant_id=[string]$grant.grant_id; source_hash=$sourceHash; data_as_of=[string]$input.as_of
  action_cards=@($cards); dispatch_ready=$false; external_calls=$false; write_performed=$false
  approval_required=($cards.Count -gt 0); independent_verification_required=$true
}) 0
