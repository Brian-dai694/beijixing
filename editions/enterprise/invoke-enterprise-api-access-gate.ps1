<##
.SYNOPSIS
  Offline API minimum-access gate. It validates a request and returns a
  broker execution plan; it never calls a provider or reads secret values.
##>
param(
  [ValidateSet('example_readonly','example_controlled_write')][string]$ProviderProfile,
  [ValidateSet('read_selected','analyze','prepare_write','execute_write')][string]$Operation,
  [ValidateSet('public','internal_sanitized','confidential_reference_only','restricted_secret')][string]$DataClassification = 'public',
  [string]$TaskId = '', [string]$GrantId = '', [string]$ProviderId = '', [string]$CredentialRef = '',
  [string]$Purpose = '', [string]$TimeRange = '', [string]$DataScope = '', [string]$Budget = '',
  [string]$RequestedFields = '', [string]$BodyFields = '',
  [switch]$ActiveGrant, [switch]$ApprovedOperator, [switch]$SecondConfirmation,
  [switch]$PreflightSnapshot, [switch]$IdempotencyKey, [switch]$RollbackRef,
  [switch]$IndependentVerifier, [switch]$SanitizedEvidence, [switch]$SecretScanPassed, [switch]$PersonalDataScanPassed, [switch]$ScopeScanPassed, [switch]$FieldAllowlistScanPassed, [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$policyPath = Join-Path $PSScriptRoot 'api-access-policy.json'
$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$reasons = [System.Collections.Generic.List[string]]::new()
$profile = $policy.provider_profiles.$ProviderProfile
$requestedFieldList = @($RequestedFields -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$bodyFieldList = @($BodyFields -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($null -eq $profile) { [void]$reasons.Add('provider_profile_not_registered') }
foreach ($item in @(@('task_id',$TaskId),@('grant_id',$GrantId),@('provider_id',$ProviderId),@('purpose',$Purpose),@('time_range',$TimeRange),@('data_scope',$DataScope),@('budget',$Budget),@('credential_ref',$CredentialRef))) {
  if ([string]::IsNullOrWhiteSpace([string]$item[1])) { [void]$reasons.Add("missing_$($item[0])") }
}
if ($CredentialRef -notmatch '^secretref:(env|os|manager)/[A-Za-z0-9._/-]+$') { [void]$reasons.Add('credential_must_be_local_secret_reference') }
if ($CredentialRef -match '(?i)(sk-|bearer|password=|token=|secret=)') { [void]$reasons.Add('credential_value_not_accepted') }
if ($DataClassification -eq 'restricted_secret') { [void]$reasons.Add('restricted_secret_payload_denied') }
if ($null -ne $profile) {
  if (@($profile.allowed_operations) -notcontains $Operation) { [void]$reasons.Add('operation_not_allowed_by_provider_profile') }
  foreach ($field in $requestedFieldList) { if (@($profile.allowed_request_fields) -notcontains $field) { [void]$reasons.Add("request_field_not_allowlisted_$field") } }
  foreach ($field in $bodyFieldList) { if (@($profile.allowed_body_fields) -notcontains $field) { [void]$reasons.Add("body_field_not_allowlisted_$field") } }
  foreach ($field in @($requestedFieldList + $bodyFieldList)) { if (@($profile.denied_fields) -contains $field) { [void]$reasons.Add("sensitive_field_denied_$field") } }
}
if ($Operation -in @('read_selected','analyze') -and $requestedFieldList.Count -eq 0) { [void]$reasons.Add('selected_fields_required') }
if ($Operation -in @('prepare_write','execute_write')) {
  if ($bodyFieldList.Count -eq 0) { [void]$reasons.Add('allowlisted_body_fields_required') }
  if ($Operation -eq 'execute_write') {
    foreach ($item in @(@('active_grant',$ActiveGrant),@('approved_operator',$ApprovedOperator),@('second_confirmation',$SecondConfirmation),@('preflight_snapshot',$PreflightSnapshot),@('idempotency_key',$IdempotencyKey),@('rollback_ref',$RollbackRef))) { if (-not [bool]$item[1]) { [void]$reasons.Add("$($item[0])_required_for_L4") } }
  }
}
if ($Operation -in @('prepare_write','execute_write') -or $DataClassification -in @('confidential_reference_only')) {
  if (-not $IndependentVerifier -or -not $SanitizedEvidence) { [void]$reasons.Add('independent_sanitized_verification_required') }
  foreach ($scan in @(@('secret_scan',$SecretScanPassed),@('personal_data_scan',$PersonalDataScanPassed),@('scope_scan',$ScopeScanPassed),@('field_allowlist_scan',$FieldAllowlistScanPassed))) { if (-not [bool]$scan[1]) { [void]$reasons.Add("$($scan[0])_required_before_model_verification") } }
}
$status = if ($reasons.Count -eq 0) { if ($Operation -eq 'execute_write') { 'broker_plan_ready_after_confirmation' } else { 'broker_plan_allowed' } } else { 'blocked' }
$result = [ordered]@{
  status = $status; task_id = $TaskId; grant_id = $GrantId; provider_id = $ProviderId; operation = $Operation
  required_level = if ($Operation -eq 'execute_write') { 'L4' } elseif ($Operation -eq 'prepare_write' -or $DataClassification -eq 'confidential_reference_only') { 'L3' } else { 'L2' }
  requested_fields = @($requestedFieldList); body_fields = @($bodyFieldList); response_projection = if ($null -ne $profile) { @($profile.response_projection) } else { @() }
  credential_value_exposed = $false; raw_payload_to_model = $false; provider_called = $false; network_opened = $false; permissions_granted = $false
  agent_receives = 'sanitized_projected_result_only'; execution_path = 'broker_allowlisted_adapter'; reasons = @($reasons)
}
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { [PSCustomObject]$result | Format-List }
if ($status -eq 'blocked') { exit 1 }
