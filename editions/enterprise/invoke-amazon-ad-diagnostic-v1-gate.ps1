param(
  [Parameter(Mandatory = $true)][string]$ActionCardPath,
  [ValidateSet('plan','execute')][string]$Mode = 'plan',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$contractPath = Join-Path $PSScriptRoot 'amazon-ad-diagnostic-v1-contract.json'
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$card = Get-Content -LiteralPath $ActionCardPath -Raw -Encoding UTF8 | ConvertFrom-Json
$missing = @($contract.action_card_required_fields | Where-Object { -not ($card.PSObject.Properties.Name -contains $_) })
$status = 'diagnosed'
$reason = 'read_only_plan'
$required = @()

if ($missing.Count -gt 0) {
  $status = 'blocked'; $reason = 'missing_action_card_fields'; $required = $missing
} elseif ($Mode -eq 'execute') {
  $required = @($contract.required_change_controls)
  $missingControls = @($required | Where-Object { -not ($card.PSObject.Properties.Name -contains $_) -or [string]::IsNullOrWhiteSpace([string]$card.$_) })
  if ($missingControls.Count -gt 0) {
    $status = 'approval_required'; $reason = 'change_controls_missing'; $required = $missingControls
  } elseif ($card.authority -ne 'approved_l4_write') {
    $status = 'approval_required'; $reason = 'human_approval_required'
  } else {
    $status = 'approved_for_runner'; $reason = 'broker_may_dispatch_bounded_work_order'
  }
}

$result = [PSCustomObject]@{
  workflow_id = $contract.workflow_id
  status = $status
  reason = $reason
  mode = $Mode
  external_write_performed = $false
  execution_authority_granted = $false
  required_fields = $required
  readback_windows = @($contract.readback_windows)
}
if ($PassThru) { $result | ConvertTo-Json -Depth 8 }
else { $result }
if ($status -eq 'blocked') { exit 1 }
