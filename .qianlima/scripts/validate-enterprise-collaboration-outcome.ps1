param([Parameter(Mandatory)][string]$OutcomePath,[string]$ContractPath='',[switch]$PassThru)
$ErrorActionPreference='Stop';$root=(Resolve-Path(Join-Path $PSScriptRoot '..')).Path;if([string]::IsNullOrWhiteSpace($ContractPath)){$ContractPath=Join-Path $root 'enterprise-collaboration-outcome-contract.json'}
$contract=Get-Content $ContractPath -Raw -Encoding UTF8|ConvertFrom-Json;$o=Get-Content $OutcomePath -Raw -Encoding UTF8|ConvertFrom-Json;$issues=[System.Collections.Generic.List[string]]::new()
function Missing($v){if($null -eq $v){return $true};if($v -is [System.Array]){return ($v.Count -eq 0)};return [string]::IsNullOrWhiteSpace([string]$v)}
function V($obj,$name){$p=$obj.PSObject.Properties[$name];if($null -eq $p){return $null};return $p.Value}
foreach($f in $contract.required_fields){if(Missing(V $o $f)){[void]$issues.Add("missing_$f")}}
if([string]$o.final_status-notin@($contract.final_statuses)){[void]$issues.Add('invalid_final_status')}
foreach($claim in @($o.claims)){foreach($f in $contract.claim_required_fields){if(Missing(V $claim $f)){[void]$issues.Add("claim_${f}_required")}};foreach($ref in @($claim.evidence_receipt_refs)){if(@($o.evidence_receipts)-notcontains[string]$ref){[void]$issues.Add('claim_evidence_receipt_missing')}}}
if([double]$o.budget_used.cost_usd -gt [double]$o.budget_authorized.cost_usd -or [int]$o.budget_used.tool_calls -gt [int]$o.budget_authorized.tool_calls){[void]$issues.Add('budget_exceeded')}
switch([string]$o.final_status){
  'blocked'{if(Missing $o.blocker_reasons){[void]$issues.Add('blocked_reasons_required')};if(-not(Missing $o.failure_evidence_receipt_refs)){[void]$issues.Add('blocked_cannot_claim_observed_failure')}}
  'failed'{if(Missing $o.failure_evidence_receipt_refs){[void]$issues.Add('failed_requires_failure_evidence')}}
  'completed'{if($o.verification_passed -ne $true){[void]$issues.Add('completed_requires_verification')};if([string]$o.risk_level -eq 'L4' -and $o.candidate_only -ne $true){[void]$issues.Add('L4_completed_must_be_candidate_only')}}
  'cancelled'{if($o.revocation_confirmed -ne $true){[void]$issues.Add('cancelled_requires_revocation_confirmation')}}
}
if($o.reversible -ne $true){if(Missing $o.approval_ref){[void]$issues.Add('irreversible_approval_required')};if(Missing $o.compensation_or_rollback_ref){[void]$issues.Add('irreversible_compensation_required')}}
$result=[ordered]@{status=if($issues.Count){'rejected'}else{'validated'};outcome_id=$o.outcome_id;final_status=$o.final_status;issues=@($issues);grants_issued=$false;memory_promoted=$false;production_authority='none';external_calls=$false};if($PassThru){$result|ConvertTo-Json -Depth 7}else{[pscustomobject]$result|Format-List};if($issues.Count){exit 2}
