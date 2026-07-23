$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$contract = Get-Content -LiteralPath (Join-Path $root 'amazon-ad-diagnostic-v1-contract.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$gate = Join-Path $root 'invoke-amazon-ad-diagnostic-v1-gate.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('beijixing-ad-v1-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  $valid = [ordered]@{ problem='high acos'; evidence=@{source_ref='fixture.csv';source_hash='sha256:test';time_range='2026-07-01/2026-07-14';metric_definition='acos';before_value=0.45;proposed_value=0.32}; recommendation='lower_bid'; impact='bounded'; authority='plan_only'; rollback='restore previous bid'; verification=@('3d','7d') }
  $validPath = Join-Path $temp 'valid.json'; $valid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $validPath -Encoding UTF8
  $r1 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate -ActionCardPath $validPath -Mode plan -PassThru | ConvertFrom-Json
  $r2 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate -ActionCardPath $validPath -Mode execute -PassThru | ConvertFrom-Json
  $approved = [ordered]@{ problem='high acos'; evidence=@{source_ref='fixture.csv';source_hash='sha256:test';time_range='2026-07-01/2026-07-14';metric_definition='acos';before_value=0.45;proposed_value=0.32}; recommendation='lower_bid'; impact='bounded'; authority='approved_l4_write'; rollback='restore previous bid'; verification=@('3d','7d'); grant_id='grant-1'; approval_ref='approval-1'; pre_change_snapshot='snap-1'; idempotency_key='idem-1'; rollback_ref='rollback-1'; post_change_readback='pending' }; $approvedPath=Join-Path $temp 'approved.json'; $approved | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $approvedPath -Encoding UTF8
  $r3 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate -ActionCardPath $approvedPath -Mode execute -PassThru | ConvertFrom-Json
  [PSCustomObject]@{
    read_plan_is_diagnosed = ($r1.status -eq 'diagnosed' -and $r1.external_write_performed -eq $false)
    unapproved_write_is_blocked = ($r2.status -eq 'approval_required' -and $r2.external_write_performed -eq $false)
    approved_card_is_runner_candidate_only = ($r3.status -eq 'approved_for_runner' -and $r3.execution_authority_granted -eq $false -and $r3.external_write_performed -eq $false)
    readback_windows_required = (@($contract.readback_windows).Count -eq 2)
  }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
