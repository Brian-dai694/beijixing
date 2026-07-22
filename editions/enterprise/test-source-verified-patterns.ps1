<# .SYNOPSIS Offline regression for source-verified Helmsman, OpenSEO, and Apollo-11 mappings. #>
param([switch]$PassThru)
$ErrorActionPreference='Stop'
$hostPath=(Get-Process -Id $PID).Path
$serviceContract=Get-Content (Join-Path $PSScriptRoot 'enterprise-service-boundary-contract.json') -Raw -Encoding UTF8|ConvertFrom-Json
$selfContract=Get-Content (Join-Path $PSScriptRoot 'runtime-self-check-contract.json') -Raw -Encoding UTF8|ConvertFrom-Json
$serviceGate=Join-Path $PSScriptRoot 'invoke-enterprise-service-gate.ps1'
$selfGate=Join-Path $PSScriptRoot 'invoke-runtime-self-check-gate.ps1'
$cases=[System.Collections.Generic.List[object]]::new()
function Add([string]$n,[bool]$p){$cases.Add([pscustomobject]@{name=$n;passed=$p})}
function Run([string]$path,[object]$InputArguments){$Arguments=[string[]]@($InputArguments);$oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue';$out=@(& $hostPath -NoProfile -File $path @Arguments -PassThru 2>&1);$ErrorActionPreference=$oldPreference;$code=$LASTEXITCODE;$value=$null;try{$value=($out-join[Environment]::NewLine)|ConvertFrom-Json}catch{};[pscustomobject]@{code=$code;value=$value}}
$base=@('-TaskId','t1','-GrantId','g1','-OrganizationId','o1','-ProjectId','p1','-StoreId','s1','-Marketplace','US','-ProductLine','line1','-GrantOrganizationId','o1','-GrantProjectId','p1','-GrantStoreId','s1','-SecretReference','secretref:data-provider','-OwnershipVerified','-GrantActive','-BudgetAvailable','-AdapterAllowlisted')
Add 'service_repository_mcp_layers_are_shared' ($serviceContract.layers.Count-eq 5-and$serviceContract.production_authority-eq'none')
$ui=Run $serviceGate (@('-CallerType','ui_user','-Operation','read','-RiskLevel','L2')+$base)
Add 'ui_read_plan_is_allowed_without_execution' ($ui.code-eq 0-and$ui.value.status-eq'service_plan_allowed'-and-not$ui.value.execution_authorized)
$mcp=Run $serviceGate (@('-CallerType','mcp_agent','-Operation','read','-RiskLevel','L2')+$base)
Add 'mcp_requires_oauth' ($mcp.code-ne 0-and@($mcp.value.reasons)-contains'mcp_oauth_required')
$mcpOk=Run $serviceGate (@('-CallerType','mcp_agent','-Operation','read','-RiskLevel','L2','-OAuthValidated')+$base)
Add 'oauth_does_not_become_task_authority' ($mcpOk.code-eq 0-and-not$mcpOk.value.oauth_is_task_authority)
$scopeArgs=[System.Collections.Generic.List[string]](@('-CallerType','ui_user','-Operation','read','-RiskLevel','L2')+$base);$scopeArgs[$scopeArgs.IndexOf('p1',$scopeArgs.IndexOf('-GrantProjectId'))]='other';$scope=Run $serviceGate $scopeArgs.ToArray()
Add 'project_scope_mismatch_is_denied' ($scope.code-ne 0-and@($scope.value.reasons)-contains'grant_scope_mismatch')
$schedule=Run $serviceGate (@('-CallerType','scheduled_agent','-Operation','read','-RiskLevel','L2')+$base)
Add 'scheduled_agent_requires_independent_identity' ($schedule.code-ne 0-and@($schedule.value.reasons)-contains'scheduled_service_identity_required')
$write=Run $serviceGate (@('-CallerType','ui_user','-Operation','execute_write','-RiskLevel','L4')+$base)
Add 'business_write_remains_disabled' ($write.code-ne 0-and@($write.value.reasons)-contains'business_write_disabled_this_release')
Add 'self_check_contract_is_non_destructive' ($selfContract.non_destructive-and$selfContract.background_priority-eq 0-and$selfContract.production_authority-eq'none')
$startup=Run $selfGate @('-Tier','Startup','-Result','Pass','-CheckId','c1','-SessionId','session1','-StateRestored')
Add 'startup_check_can_report_healthy' ($startup.code-eq 0-and$startup.value.status-eq'healthy')
$background=Run $selfGate @('-Tier','Background','-Result','Pass','-CheckId','c2','-SessionId','session1','-Priority','1','-Preemptible','-StateRestored')
Add 'background_check_must_be_zero_priority' ($background.code-ne 0-and@($background.value.reasons)-contains'background_priority_must_be_zero')
$failure=Run $selfGate @('-Tier','Background','-Result','Fail','-CheckId','c3','-SessionId','session1','-Preemptible','-StateRestored','-FailureLocation','workflow:x','-ContextRef','ctx1','-SourceRef','source1','-CumulativeCount','2','-RecoveryAction','degrade_capability')
Add 'failure_records_location_count_and_recovery' ($failure.code-eq 0-and$failure.value.status-eq'degraded'-and$failure.value.failure_receipt_required)
$l4=Run $selfGate @('-Tier','L4Preflight','-Result','Pass','-CheckId','c4','-SessionId','session1','-TaskId','t1','-GrantId','g1','-GrantActive','-StateRestored')
Add 'L4_requires_fresh_authoritative_data' ($l4.code-ne 0-and@($l4.value.reasons)-contains'L4_fresh_data_required')
$mutate=Run $selfGate @('-Tier','Startup','-Result','Pass','-CheckId','c5','-SessionId','session1','-StateRestored','-ProductionMutated')
Add 'self_check_cannot_mutate_production' ($mutate.code-ne 0-and@($mutate.value.reasons)-contains'self_check_must_not_mutate_production')
$failed=@($cases|Where-Object{-not$_.passed})
$result=[pscustomobject]@{passed=($failed.Count-eq 0);cases=@($cases);listeners_opened=$false;processes_started=$false;external_calls=$false;files_written=$false;permissions_granted=$false}
if($PassThru){$result|ConvertTo-Json -Depth 8}else{$cases|Format-Table -AutoSize}
if($failed.Count-gt 0){throw "Source-verified pattern regression failed: $($failed.name-join', ')"}
