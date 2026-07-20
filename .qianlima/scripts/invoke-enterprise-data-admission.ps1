<#
.SYNOPSIS
  Builds a layered enterprise evidence pack after hard policy admission.
#>
param(
  [Parameter(Mandatory=$true)][string]$RequestPath,
  [Parameter(Mandatory=$true)][string]$GrantPath,
  [Parameter(Mandatory=$true)][string]$CandidatePath,
  [switch]$PassThru
)

$ErrorActionPreference='Stop'
$request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8|ConvertFrom-Json
$grant=Get-Content -LiteralPath $GrantPath -Raw -Encoding UTF8|ConvertFrom-Json
$input=Get-Content -LiteralPath $CandidatePath -Raw -Encoding UTF8|ConvertFrom-Json
$issues=[System.Collections.Generic.List[string]]::new()

foreach($f in @('request_id','task_id','agent_id','grant_id','organization_id','department_id','project_id','device_id','device_attestation','purpose','risk_level','target','max_items','allowed_classifications','now')){
  if($null-eq$request.$f-or[string]::IsNullOrWhiteSpace([string]$request.$f)){[void]$issues.Add("request_${f}_required")}
}
if($request.target-notin@('internal_agent','external_agent')){[void]$issues.Add('target_denied')}
if($request.device_attestation-ne'verified'){[void]$issues.Add('verified_device_attestation_required')}
if($grant.status-ne'issued'){[void]$issues.Add('grant_not_issued')}
if($grant.task_id-ne$request.task_id-or$grant.agent_id-ne$request.agent_id-or$grant.grant_id-ne$request.grant_id){[void]$issues.Add('task_agent_grant_mismatch')}
if($grant.organization_id-ne$request.organization_id-or$grant.department_id-ne$request.department_id-or$grant.project_id-ne$request.project_id-or$grant.device_id-ne$request.device_id){[void]$issues.Add('organization_or_device_grant_mismatch')}
$now=[datetime]::MinValue
if(-not[datetime]::TryParse([string]$request.now,[ref]$now)){[void]$issues.Add('invalid_request_time')}
elseif($now.ToUniversalTime()-ge([datetime]$grant.expires_at).ToUniversalTime()){[void]$issues.Add('grant_expired')}
$max=[int]$request.max_items
if($max-lt1-or$max-gt20){[void]$issues.Add('max_items_out_of_bounds')}
if($null-ne$grant.budget.max_evidence_items-and$max-gt[int]$grant.budget.max_evidence_items){[void]$issues.Add('top_k_exceeds_grant_budget')}
if($issues.Count){
  $r=[ordered]@{status='denied';stage='L0_policy_context';issues=@($issues);candidates_ranked=0;evidence_returned=0;search_capability_granted=$false;permissions_granted=$false}
  if($PassThru){$r|ConvertTo-Json -Depth 8}else{[pscustomobject]$r|Format-List};exit 1
}

$denied=[System.Collections.Generic.List[object]]::new()
$eligible=[System.Collections.Generic.List[object]]::new()
$allowedClasses=@($request.allowed_classifications)
if($request.target-eq'external_agent'){$allowedClasses=@($allowedClasses|Where-Object{$_-in@('public','internal_sanitized')})}

foreach($c in @($input.candidates)){
  $reasons=[System.Collections.Generic.List[string]]::new()
  foreach($f in @('evidence_id','source_type','source_ref','version','classification','organization_id','department_id','project_id','state','valid_from','valid_to','retention_until','verification_status','content_sha256','sanitized_excerpt','relevance_score','evidence_quality','freshness_score','retrieval_cost','exposure_risk')){
    if($null-eq$c.$f-or[string]::IsNullOrWhiteSpace([string]$c.$f)){[void]$reasons.Add("${f}_required")}
  }
  if(@($grant.data_refs)-notcontains$c.source_ref){[void]$reasons.Add('outside_grant_data_refs')}
  if($allowedClasses-notcontains$c.classification){[void]$reasons.Add('classification_denied')}
  if($c.organization_id-ne$request.organization_id-or$c.department_id-ne$request.department_id-or$c.project_id-ne$request.project_id){[void]$reasons.Add('organization_scope_denied')}
  if($c.state-ne'current'){[void]$reasons.Add('non_current')}
  if(-not[string]::IsNullOrWhiteSpace([string]$c.revoked_at)){[void]$reasons.Add('revoked')}
  if($now.ToUniversalTime()-lt([datetime]$c.valid_from).ToUniversalTime()-or$now.ToUniversalTime()-ge([datetime]$c.valid_to).ToUniversalTime()){[void]$reasons.Add('outside_validity')}
  if($now.ToUniversalTime()-ge([datetime]$c.retention_until).ToUniversalTime()){[void]$reasons.Add('retention_expired')}
  if($c.verification_status-notin@('verified','independently_verified')){[void]$reasons.Add('unverified')}
  if([string]$c.content_sha256-notmatch'^[a-fA-F0-9]{64}$'){[void]$reasons.Add('invalid_content_hash')}
  foreach($scoreField in @('relevance_score','evidence_quality','freshness_score','retrieval_cost','exposure_risk')){if([double]$c.$scoreField-lt0-or[double]$c.$scoreField-gt1){[void]$reasons.Add("${scoreField}_out_of_bounds")}}
  if($null-ne$c.raw_content-or$null-ne$c.absolute_path-or$null-ne$c.secret_value){[void]$reasons.Add('prohibited_payload_field')}
  if($reasons.Count){
    $denied.Add([pscustomobject]@{evidence_id=$c.evidence_id;admissible=$false;reasons=@($reasons)})
  }else{
    $score=.40*[double]$c.relevance_score+.25*[double]$c.evidence_quality+.15*[double]$c.freshness_score-.10*[double]$c.retrieval_cost-.10*[double]$c.exposure_risk
    $eligible.Add([pscustomobject]@{record=$c;score=[math]::Round($score,6)})
  }
}

$ranked=@($eligible|Sort-Object score -Descending)
$selected=@($ranked|Select-Object -First $max)
$notSelected=@($ranked|Select-Object -Skip $max|ForEach-Object{[ordered]@{evidence_id=$_.record.evidence_id;admissible=$true;reason='below_top_k';rank_score=$_.score}})
$metadata=@($eligible|ForEach-Object{$c=$_.record;[ordered]@{evidence_id=$c.evidence_id;source_type=$c.source_type;source_ref=$c.source_ref;version=$c.version;classification=$c.classification;valid_from=$c.valid_from;valid_to=$c.valid_to;verification_status=$c.verification_status;content_sha256=([string]$c.content_sha256).ToLowerInvariant()}})
$items=@($selected|ForEach-Object{$c=$_.record;[ordered]@{evidence_id=$c.evidence_id;source_ref=$c.source_ref;version=$c.version;classification=$c.classification;valid_from=$c.valid_from;valid_to=$c.valid_to;verification_status=$c.verification_status;content_sha256=([string]$c.content_sha256).ToLowerInvariant();sanitized_excerpt=$c.sanitized_excerpt;rank_score=$_.score;score_components=[ordered]@{relevance=[double]$c.relevance_score;evidence_quality=[double]$c.evidence_quality;freshness=[double]$c.freshness_score;retrieval_cost_penalty=[double]$c.retrieval_cost;exposure_risk_penalty=[double]$c.exposure_risk};selection_reason='admissible_then_top_k_by_explicit_governance_score'}})
$originalRefs=@($selected|ForEach-Object{$c=$_.record;[ordered]@{evidence_id=$c.evidence_id;source_ref=$c.source_ref;version=$c.version;content_sha256=([string]$c.content_sha256).ToLowerInvariant();original_content_included=$false;jit_read_requirement='new_task_bound_grant_and_policy_recheck'}})

$result=[ordered]@{
  status='allowed';request_id=$request.request_id;task_id=$request.task_id;grant_id=$request.grant_id;agent_id=$request.agent_id;target=$request.target
  layers=[ordered]@{
    L0_policy_context=[ordered]@{organization_id=$request.organization_id;department_id=$request.department_id;project_id=$request.project_id;device_id=$request.device_id;grant_id=$request.grant_id;risk_level=$request.risk_level;allowed_classifications=$allowedClasses;visibility='broker_and_audit_only'}
    L1_metadata_index=[ordered]@{items=$metadata;visibility='broker_only'}
    L2_candidate_evidence=[ordered]@{items=$items;visibility='task_selected_dispatch_payload';sanitized=$true}
    L3_original_references=[ordered]@{items=$originalRefs;visibility='broker_reference_only';original_content_included=$false}
  }
  dispatch_payload=[ordered]@{layer='L2_candidate_evidence';items=$items;knowledge_search_capability=$false}
  policy_filter_applied_before_ranking=$true;learned_end_to_end_selector_used=$false;candidate_count=@($input.candidates).Count;eligible_count=$eligible.Count;denied_count=$denied.Count;denied_candidates=@($denied);not_selected_candidates=$notSelected;top_k=$max
  evidence_pack=$items;search_capability_granted=$false;raw_paths_returned=$false;raw_private_content_returned=$false;original_content_returned=$false;permissions_granted=$false;external_calls=$false;adoption_authority='none'
}
if($PassThru){$result|ConvertTo-Json -Depth 14}else{[pscustomobject]$result|Format-List}
