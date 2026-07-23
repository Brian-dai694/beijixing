<##
.SYNOPSIS
  Validates one enterprise Task Runtime Spec without executing it.
##>
param([string]$SpecPath='', [string]$SpecJson='', [switch]$PassThru)
$ErrorActionPreference='Stop';$reasons=[System.Collections.Generic.List[string]]::new()
if([string]::IsNullOrWhiteSpace($SpecPath)-eq[string]::IsNullOrWhiteSpace($SpecJson)){throw'Provide exactly one of SpecPath or SpecJson.'}
if($SpecPath){if(-not(Test-Path -LiteralPath $SpecPath -PathType Leaf)){throw'SpecPath does not exist.'};$SpecJson=Get-Content -LiteralPath $SpecPath -Raw -Encoding UTF8}
$spec=$SpecJson|ConvertFrom-Json;$contract=Get-Content -LiteralPath(Join-Path $PSScriptRoot 'task-runtime-spec-contract.json')-Raw -Encoding UTF8|ConvertFrom-Json
function Has($Object,[string]$Name){$null-ne$Object-and$null-ne$Object.PSObject.Properties[$Name]-and-not[string]::IsNullOrWhiteSpace([string]$Object.$Name)}
function Need($Object,[string]$Name,[string]$Prefix=''){if(-not(Has $Object $Name)){[void]$reasons.Add("missing_$Prefix$Name")}}
foreach($field in @('spec_id','spec_version','task_id','tenant_id','organization_id','project_id','human_owner_id','goal','risk_level')){Need $spec $field}
if([string]$spec.risk_level-notin@('L1','L2','L3','L4')){[void]$reasons.Add('unsupported_risk_level')}
foreach($field in @('profile_id','allowed_tools')){Need $spec.capability_profile $field 'capability_'}
foreach($field in @('classification','source_refs','allowed_fields','expires_at')){Need $spec.data_scope $field 'data_scope_'}
foreach($field in @('max_steps','max_tool_calls','max_cost','max_runtime_seconds','max_output_bytes')){Need $spec.budget $field 'budget_';if((Has $spec.budget $field)-and[double]$spec.budget.$field-le0){[void]$reasons.Add("budget_$($field)_must_be_positive")}}
$states=@($spec.state_machine.states|ForEach-Object{[string]$_});$transitions=@($spec.state_machine.transitions|ForEach-Object{[string]$_});$terminals=@($spec.state_machine.terminal_states|ForEach-Object{[string]$_})
foreach($state in @($contract.state_contract.required_states)){if($states-notcontains[string]$state){[void]$reasons.Add("missing_state_$state")}}
foreach($transition in @($contract.state_contract.required_transitions)){if($transitions-notcontains[string]$transition){[void]$reasons.Add("missing_transition_$transition")}}
foreach($terminal in @('completed','blocked','frozen','cancelled')){if($terminals-notcontains$terminal){[void]$reasons.Add("missing_terminal_$terminal")}}
$confirm=@($spec.confirmation_points|ForEach-Object{[string]$_});if([string]$spec.risk_level-eq'L4'){foreach($control in @($contract.l4_controls)){if($confirm-notcontains[string]$control){[void]$reasons.Add("L4_$($control)_required")}}}
$evidence=@($spec.required_evidence|ForEach-Object{[string]$_});foreach($item in @($contract.required_evidence)){if($evidence-notcontains[string]$item){[void]$reasons.Add("missing_evidence_$item")}}
foreach($field in @($contract.failure_requirements)){Need $spec.failure_policy ([string]$field) 'failure_'}
foreach($field in @('producer_id','independent_verifier_id','replay_ref','acceptance_matrix_ref')){Need $spec.verification $field 'verification_'}
if((Has $spec.verification 'producer_id')-and$spec.verification.producer_id-eq$spec.verification.independent_verifier_id){[void]$reasons.Add('self_verification_denied')}
foreach($field in @('grant_id','attestation_ref','policy_version','audit_sink_ref')){Need $spec.governance $field 'governance_'}
if($spec.execution.authorized-eq$true){[void]$reasons.Add('spec_cannot_grant_execution')};if($spec.execution.external_write-eq$true){[void]$reasons.Add('external_write_disabled')};if($spec.execution.production_write-eq$true){[void]$reasons.Add('production_write_disabled')}
if([string]$spec.improvement.mode-ne'candidate_only'){[void]$reasons.Add('improvement_must_be_candidate_only')};if($spec.improvement.auto_apply-eq$true){[void]$reasons.Add('improvement_auto_apply_denied')}
foreach($target in @($spec.improvement.target_files)){foreach($forbidden in @($contract.improvement_loop.forbidden_targets)){if([string]$target-match[regex]::Escape([string]$forbidden)){[void]$reasons.Add("forbidden_improvement_target_$forbidden")}}}
$status=if($reasons.Count){'blocked'}elseif([string]$spec.risk_level-eq'L4'){'needs_human'}else{'spec_valid'}
$result=[ordered]@{status=$status;spec_id=$spec.spec_id;task_id=$spec.task_id;risk_level=$spec.risk_level;execution_authorized=$false;adoption_authority='none';external_calls=$false;processes_started=$false;files_written=$false;permissions_granted=$false;etclovg_required=$true;next_step=if($status-eq'spec_valid'){'broker_review_no_execution'}elseif($status-eq'needs_human'){'human_review_candidate_no_execution'}else{'freeze_preserve_evidence_and_revoke'};reasons=@($reasons)}
if($PassThru){$result|ConvertTo-Json -Depth 8}else{[PSCustomObject]$result|Format-List};if($status-eq'blocked'){exit 1}
