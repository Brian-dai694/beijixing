<##
.SYNOPSIS
  Creates an immutable, non-executing enterprise product experiment proposal.
##>
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$')][string]$ExperimentId,
  [Parameter(Mandatory=$true)][ValidateSet('agent','model','skill','tool','mcp','data_connection','workflow','automation')][string]$SubjectType,
  [Parameter(Mandatory=$true)][string]$TargetRole,
  [Parameter(Mandatory=$true)][string]$RealScenario,
  [Parameter(Mandatory=$true)][string]$CurrentExperience,
  [Parameter(Mandatory=$true)][string]$ExpectedExperience,
  [Parameter(Mandatory=$true)][string]$CoreUserValue,
  [Parameter(Mandatory=$true)][string]$MigrationCosts,
  [Parameter(Mandatory=$true)][string]$SupplyCapabilities,
  [Parameter(Mandatory=$true)][string]$Hypothesis,
  [Parameter(Mandatory=$true)][string]$BoundedScope,
  [Parameter(Mandatory=$true)][string]$Baseline,
  [Parameter(Mandatory=$true)][string]$SuccessMetrics,
  [Parameter(Mandatory=$true)][string]$FailureMetrics,
  [Parameter(Mandatory=$true)][string]$StopConditions,
  [Parameter(Mandatory=$true)][string]$RollbackRef,
  [Parameter(Mandatory=$true)][ValidateRange(1,1000000)][int]$MaxCostUnits,
  [Parameter(Mandatory=$true)][ValidateRange(1,8760)][int]$MaxDurationHours,
  [Parameter(Mandatory=$true)][string]$OwnerId,
  [Parameter(Mandatory=$true)][string]$IndependentEvaluatorId,
  [string]$OutputPath='',
  [switch]$PassThru
)
$ErrorActionPreference='Stop';$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path;$root=[IO.Path]::GetFullPath((Join-Path $projectRoot '.qianlima/run-traces/enterprise-product-experiments')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
function Emit([hashtable]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 12}else{$Value|Format-List};if($Code-ne0){exit $Code}}
$migrationCostList=@($MigrationCosts-split';'|Where-Object{-not[string]::IsNullOrWhiteSpace($_)});$supplyList=@($SupplyCapabilities-split';'|Where-Object{-not[string]::IsNullOrWhiteSpace($_)});$successMetricList=@($SuccessMetrics-split';'|Where-Object{-not[string]::IsNullOrWhiteSpace($_)});$failureMetricList=@($FailureMetrics-split';'|Where-Object{-not[string]::IsNullOrWhiteSpace($_)});$stopConditionList=@($StopConditions-split';'|Where-Object{-not[string]::IsNullOrWhiteSpace($_)})
if($OwnerId-eq$IndependentEvaluatorId){Emit ([ordered]@{status='blocked';reason='independent_evaluator_must_differ_from_owner';experiment_written=$false}) 1}
$requiredSupply=@('identity','policy','data_guard','approval','evidence','audit','revocation_or_rollback');$missing=@($requiredSupply|Where-Object{$supplyList-notcontains$_});if($missing.Count){Emit ([ordered]@{status='blocked';reason='stable_supply_capability_missing';missing_capabilities=$missing;experiment_written=$false}) 1}
if($migrationCostList.Count-eq0-or$successMetricList.Count-eq0-or$failureMetricList.Count-eq0-or$stopConditionList.Count-eq0){Emit ([ordered]@{status='blocked';reason='migration_metrics_and_stop_conditions_required';experiment_written=$false}) 1}
$forbidden='(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|password|cookie|authorization:|raw_prompt|hidden_reasoning|secret_value|raw_customer_data)';foreach($value in @($TargetRole,$RealScenario,$CurrentExperience,$ExpectedExperience,$CoreUserValue,$Hypothesis,$BoundedScope,$Baseline,$RollbackRef,$OwnerId,$IndependentEvaluatorId)+@($MigrationCosts)+@($SuccessMetrics)+@($FailureMetrics)+@($StopConditions)){if([string]$value-match$forbidden){Emit ([ordered]@{status='blocked';reason='prohibited_sensitive_experiment_content';experiment_written=$false}) 1}}
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $root "$ExperimentId.json"};$full=[IO.Path]::GetFullPath($OutputPath);if(-not$full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){Emit ([ordered]@{status='blocked';reason='experiment_output_outside_governed_root';experiment_written=$false}) 1};if(Test-Path -LiteralPath $full){Emit ([ordered]@{status='blocked';reason='experiment_already_exists';experiment_written=$false}) 1}
$experiment=[ordered]@{schema_version=1;policy_version='2.14.0';experiment_id=$ExperimentId;subject_type=$SubjectType;status='candidate';problem=[ordered]@{target_role=$TargetRole;real_scenario=$RealScenario;current_experience=$CurrentExperience;expected_experience=$ExpectedExperience;core_user_value=$CoreUserValue;migration_costs=$migrationCostList};supply_capabilities=$supplyList;validation=[ordered]@{hypothesis=$Hypothesis;bounded_scope=$BoundedScope;baseline=$Baseline;success_metrics=$successMetricList;failure_metrics=$failureMetricList;stop_conditions=$stopConditionList;rollback_ref=$RollbackRef;max_cost_units=$MaxCostUnits;max_duration_hours=$MaxDurationHours;owner_id=$OwnerId;independent_evaluator_id=$IndependentEvaluatorId};promotion_path=@('static_check','isolated_replay','independent_evaluation','human_review','limited_pilot','regression_monitoring','promote_or_revoke');failure_action='freeze_rollback_or_abandon';execution_authorized=$false;production_authority=$false;business_write=$false;permission_expansion=$false;raw_sensitive_data=$false;created_at=[DateTime]::UtcNow.ToString('o')}
New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force|Out-Null;[IO.File]::WriteAllText($full,($experiment|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false));Emit ([ordered]@{status='candidate';experiment_id=$ExperimentId;experiment_path=$full;experiment_written=$true;execution_authorized=$false;business_write=$false;permission_expansion=$false;external_calls=$false})
