<##
.SYNOPSIS
  Offline regression for professional-tool risk levels and Profiles.
##>
param([switch]$PassThru)
$ErrorActionPreference='Stop';$gate=Join-Path $PSScriptRoot 'invoke-enterprise-tool-profile-gate.ps1';$cases=[System.Collections.Generic.List[object]]::new()
function Run-Gate([string[]]$Arguments){$old=$ErrorActionPreference;$ErrorActionPreference='Continue';$out=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate @Arguments -PassThru 2>&1);$code=$LASTEXITCODE;$ErrorActionPreference=$old;$value=$null;try{$value=($out-join"`n")|ConvertFrom-Json}catch{};[PSCustomObject]@{code=$code;value=$value}}
function Add-Case([string]$Name,[bool]$Passed){$cases.Add([PSCustomObject]@{name=$Name;passed=$Passed})}
function Set-Arg([string[]]$Arguments,[string]$Name,[string]$Value){$out=[System.Collections.Generic.List[string]]::new();for($i=0;$i-lt$Arguments.Count;$i++){if($Arguments[$i]-eq$Name){$i++;continue};[void]$out.Add($Arguments[$i])};[void]$out.Add($Name);[void]$out.Add($Value);return,$out.ToArray()}
function Remove-Arg([string[]]$Arguments,[string]$Name){$out=[System.Collections.Generic.List[string]]::new();for($i=0;$i-lt$Arguments.Count;$i++){if($Arguments[$i]-eq$Name){$i++;continue};[void]$out.Add($Arguments[$i])};return,$out.ToArray()}
$base=@('-Profile','reverse-readonly','-Operation','read_metadata','-TenantId','tenant-1','-ProjectId','project-1','-ArtifactId','artifact-1','-ArtifactSha256',('a'*64),'-SessionId','session-1','-TaskId','task-1','-GrantId','grant-1','-AgentId','agent-1','-AgentVersion','1.0.0','-DeviceId','device-1','-ToolId','ida-tool','-ToolVersion','9.0','-ToolManifestHash',('b'*64),'-AttestationStatus','verified','-GrantActive','-BudgetAvailable')
$bindings=@($base|Select-Object -Skip 4)
$read=Run-Gate $base;Add-Case 'readonly_profile_allowed'($read.code-eq0-and$read.value.status-eq'tool_plan_allowed'-and-not$read.value.process_started-and-not$read.value.network_opened)
$implicit=Run-Gate (Set-Arg $base '-ProjectId' 'current_project');Add-Case 'implicit_project_denied'($implicit.code-ne0-and@($implicit.value.reasons)-contains'implicit_resource_binding_denied')
$triage=Run-Gate (@('-Profile','reverse-triage','-Operation','detect_patterns')+$bindings+@('-IndependentEvidence'));Add-Case 'triage_requires_explicit_evidence'($triage.code-eq0-and$triage.value.risk_level-eq'R1_analysis')
$triageDenied=Run-Gate (@('-Profile','reverse-triage','-Operation','detect_patterns')+$bindings);Add-Case 'triage_without_independent_evidence_denied'($triageDenied.code-ne0-and@($triageDenied.value.reasons)-contains'independent_evidence_required')
$editBase=@('-Profile','reverse-edit','-Operation','prepare_patch')+$bindings+@('-ApprovalRef','approval-1','-HumanConfirmation','-PreflightSnapshot','-RollbackRef','-PostChangeVerification')
$edit=Run-Gate $editBase;Add-Case 'edit_is_human_gated_plan'($edit.code-eq0-and$edit.value.status-eq'needs_human_execution_confirmation'-and-not$edit.value.execution_authorized)
$editDenied=Run-Gate (Remove-Arg $editBase '-ApprovalRef');Add-Case 'edit_without_approval_denied'($editDenied.code-ne0-and@($editDenied.value.reasons)-contains'approval_ref_required_for_R2')
$debug=Run-Gate (@('-Profile','reverse-debug','-Operation','start_debugger')+$bindings);Add-Case 'debug_profile_denied'($debug.code-ne0-and@($debug.value.reasons)-contains'R3_debug_and_memory_write_denied_current_release')
$memory=Run-Gate (@('-Profile','reverse-readonly','-Operation','write_memory')+$bindings);Add-Case 'memory_write_denied_by_profile'($memory.code-ne0-and@($memory.value.reasons)-contains'operation_not_allowed_by_profile')
$receipt=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tool-risk-policy.json') -Raw -Encoding UTF8|ConvertFrom-Json;Add-Case 'evidence_and_revocation_contract_present'(@($receipt.evidence_receipt.required).Count-ge 15-and$receipt.session_controls.revoke_before_next_call-eq$true-and$receipt.session_controls.post_revoke_calls-eq'deny')
$failed=@($cases|Where-Object{-not$_.passed});$result=[PSCustomObject]@{passed=($failed.Count-eq0);cases=@($cases);processes_started=$false;network_opened=$false;memory_written=$false;permissions_granted=$false};if($PassThru){$result|ConvertTo-Json -Depth 8}else{$cases|Format-Table -AutoSize};if($failed.Count-gt 0){throw("Enterprise tool profile regression failed: "+($failed.name-join', '))}
