<# .SYNOPSIS Evaluates a startup, background, or L4 preflight self-check receipt without running probes. #>
param(
  [ValidateSet('Startup','Background','L4Preflight')][string]$Tier,
  [ValidateSet('Pass','Fail')][string]$Result,
  [ValidateSet('none','restore','retry_bounded','degrade_capability','freeze','revoke','fresh_start')][string]$RecoveryAction='none',
  [ValidateRange(0,100)][int]$Priority=0,
  [ValidateRange(0,2147483647)][int]$CumulativeCount=0,
  [string]$CheckId='', [string]$SessionId='', [string]$TaskId='', [string]$GrantId='',
  [string]$FailureLocation='', [string]$ContextRef='', [string]$SourceRef='',
  [switch]$Preemptible, [switch]$StateRestored, [switch]$ProductionMutated,
  [switch]$FreshDataValidated, [switch]$GrantActive, [switch]$PassThru
)
$ErrorActionPreference='Stop'
$reasons=[System.Collections.Generic.List[string]]::new()
if([string]::IsNullOrWhiteSpace($CheckId)){[void]$reasons.Add('check_id_required')}
if([string]::IsNullOrWhiteSpace($SessionId)){[void]$reasons.Add('session_id_required')}
if($ProductionMutated){[void]$reasons.Add('self_check_must_not_mutate_production')}
if(-not $StateRestored){[void]$reasons.Add('probe_state_restoration_required')}
if($Tier-eq'Background'){
  if($Priority-ne 0){[void]$reasons.Add('background_priority_must_be_zero')}
  if(-not $Preemptible){[void]$reasons.Add('background_check_must_be_preemptible')}
}
if($Tier-eq'L4Preflight'){
  if([string]::IsNullOrWhiteSpace($TaskId)){[void]$reasons.Add('L4_task_id_required')}
  if([string]::IsNullOrWhiteSpace($GrantId)-or-not $GrantActive){[void]$reasons.Add('L4_active_grant_required')}
  if(-not $FreshDataValidated){[void]$reasons.Add('L4_fresh_data_required')}
}
if($Result-eq'Fail'){
  if([string]::IsNullOrWhiteSpace($FailureLocation)){[void]$reasons.Add('failure_location_required')}
  if([string]::IsNullOrWhiteSpace($ContextRef)){[void]$reasons.Add('failure_context_required')}
  if([string]::IsNullOrWhiteSpace($SourceRef)){[void]$reasons.Add('failure_source_required')}
  if($CumulativeCount-lt 1){[void]$reasons.Add('failure_count_required')}
  if($RecoveryAction-eq'none'){[void]$reasons.Add('recovery_action_required')}
}
$status='blocked';$terminal='frozen'
if($reasons.Count-eq 0){
  if($Result-eq'Pass'){$status='healthy';$terminal='completed'}
  elseif($RecoveryAction-eq'revoke'){$status='revoked';$terminal='revoked'}
  elseif($RecoveryAction-in@('freeze','fresh_start')){$status='frozen';$terminal='frozen'}
  else{$status='degraded';$terminal='partial'}
}
$response=[pscustomobject]@{status=$status;tier=$Tier;check_id=$CheckId;terminal_state=$terminal;execution_authorized=$false;production_mutated=$false;external_calls=$false;processes_started=$false;permissions_granted=$false;failure_receipt_required=($Result-eq'Fail');reasons=@($reasons)}
if($PassThru){$response|ConvertTo-Json -Depth 6}else{$response|Format-List}
if($status-eq'blocked'){exit 1}