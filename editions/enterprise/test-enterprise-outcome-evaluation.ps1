param([switch]$PassThru)
$ErrorActionPreference = 'Stop'
$evaluatorPath = Join-Path $PSScriptRoot 'evaluate-enterprise-outcome.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('beijixing-outcome-evaluation-' + [Guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
function Run($name, $metrics, $constraints) {
  $input = [ordered]@{ evaluation_id = $name; candidate_id = ('candidate-' + $name); tenant_id = 'tenant-eval'; organization_id = 'org-eval'; project_id = 'project-eval'; user_id = 'owner-eval'; agent_id = 'customer-service-agent'; agent_version = 'v1'; task_id = ('task-' + $name); grant_id = ('grant-' + $name); grant_checked = $true; policy_gate_checked = $true; expected_outcome = 'Customer issue resolved with compliant handling.'; observed_evidence_refs = @('crm://case/' + $name, 'approval://case/' + $name); metrics = $metrics; constraints = $constraints }
  $path = Join-Path $tmp ($name + '.json'); [IO.File]::WriteAllText($path, ($input | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
  $raw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $evaluatorPath -InputPath $path -PassThru 2>&1); [pscustomobject]@{ code = $LASTEXITCODE; value = (($raw | ForEach-Object { $_.ToString() }) -join "`n") | ConvertFrom-Json }
}
$high = Run 'high' @{ resolution_quality=.95; compliance_quality=.95; escalation_accuracy=.9; human_review_alignment=.9; refund_risk_inverse=.9; repeat_contact_risk_inverse=.9 } @{ compliance_passed=$true; sensitive_data_handling_passed=$true; evidence_complete=$true }
$middle = Run 'middle' @{ resolution_quality=.7; compliance_quality=.7; escalation_accuracy=.7; human_review_alignment=.6; refund_risk_inverse=.6; repeat_contact_risk_inverse=.6 } @{ compliance_passed=$true; sensitive_data_handling_passed=$true; evidence_complete=$true }
$blocked = Run 'blocked' @{ resolution_quality=.95; compliance_quality=.95; escalation_accuracy=.9; human_review_alignment=.9; refund_risk_inverse=.9; repeat_contact_risk_inverse=.9 } @{ compliance_passed=$false; sensitive_data_handling_passed=$true; evidence_complete=$true }
$cases = @(
  [pscustomobject]@{name='high_score_is_recommendation_only';passed=($high.code -eq 0 -and $high.value.route -eq 'recommendation_ready' -and $high.value.execution_authorized -eq $false -and $high.value.action_gate_required -eq $true)},
  [pscustomobject]@{name='medium_score_routes_to_human';passed=($middle.code -eq 0 -and $middle.value.route -eq 'human_review_required' -and $middle.value.execution_authorized -eq $false)},
  [pscustomobject]@{name='constraint_failure_freezes_even_with_high_score';passed=($blocked.code -eq 0 -and $blocked.value.route -eq 'freeze_and_escalate' -and $blocked.value.constraints_passed -eq $false)},
  [pscustomobject]@{name='score_does_not_reward_case_closure_rate';passed=((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'enterprise-outcome-evaluation-policy.json') -Raw -Encoding UTF8) -match 'case_closure_rate_is_not_a_reward_dimension')}
)
$failed = @($cases | Where-Object { -not $_.passed }); $result = [pscustomobject]@{passed=($failed.Count -eq 0); cases=$cases; external_calls=$false; business_write=$false; execution_authorized=$false}
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { $cases | Format-Table -AutoSize }; if ($failed.Count) { throw ('Enterprise outcome evaluation regression failed: ' + (($failed.name) -join ', ')) }
