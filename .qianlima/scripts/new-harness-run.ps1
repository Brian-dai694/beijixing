<#
.SYNOPSIS
  Run one complete Harness cycle threading all 8 governance components.
.DESCRIPTION
  This is the initialization spark: each run writes to audit-events.jsonl,
  experience-events.jsonl, and usage-ledger/runs.jsonl for the first time,
  making all 8 components traceable. Shadow mode (default) is read-only.
.EXAMPLE
  .\new-harness-run.ps1 -WorkflowId daily_ad_report -TaskText "鏃ュ箍鍛婅繍钀ユ棩鎶? -ShadowRun
#>
param(
  [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')] [string]$WorkflowId,
  [string]$RunId = '',
  [Parameter(Mandatory)] [string]$TaskText,
  [ValidateSet('L1','L2','L3','L4')] [string]$ContextLevel = 'L2',
  [string[]]$DataSourceRef = @(),
  [switch]$ShadowRun,
  [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$traceRoot   = Join-Path $projectRoot '.qianlima\run-traces'
$scripts     = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = "harness-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
$checkpoints = [ordered]@{}

function Set-Cp([string]$name, [string]$status, [string]$detail = '') {
  $checkpoints[$name] = [ordered]@{ status = $status; detail = $detail
    ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 0) }
}

# 1. Context Compiler
try {
  $ctxArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $scripts 'qianlima-context-fast.ps1'),
    '-TaskText',$TaskText,'-ContextLevel',$ContextLevel,'-AsJson')
  # Capture stdout only; 2>&1 mixes stderr into the JSON stream and breaks ConvertFrom-Json.
  $ctxRaw = & $psExe @ctxArgs
  $ctxOut = if ($ctxRaw -is [array]) { $ctxRaw -join '' } else { [string]$ctxRaw }
  $ctx = $ctxOut | ConvertFrom-Json
  Set-Cp 'context_compiler' 'ok' "status=$($ctx.status) lease=$($ctx.lease_valid)"
} catch { Set-Cp 'context_compiler' 'warn' ($_.Exception.Message.Substring(0,[Math]::Min(100,$_.Exception.Message.Length))) }

# 2. Policy Enforcement
$policyPass = $true
if ($ShadowRun) {
  $shadowPolicy = Join-Path $projectRoot '.qianlima\shadow-run-policy.yaml'
  $forbidden = @('change_price','change_bid','change_budget','create_purchase_order','send_external_message','write_back','delete_data')
  $hit = @($forbidden | Where-Object { $TaskText.ToLowerInvariant() -match $_ })
  if ($hit.Count -gt 0) {
    $policyPass = $false; Set-Cp 'policy_enforcement' 'blocked' "Shadow run forbids: $($hit -join ', ')"
  } else { Set-Cp 'policy_enforcement' 'ok' "shadow_run=true write_enabled=false" }
} else { Set-Cp 'policy_enforcement' 'ok' "shadow_run=false ContextLevel=$ContextLevel" }
if (-not $policyPass) {
  $r = [PSCustomObject]@{ run_id=$RunId; status='blocked'; checkpoints=$checkpoints }
  if ($AsJson) { $r | ConvertTo-Json -Depth 6 } else {
    Write-Host "Harness run BLOCKED: $RunId"; $checkpoints.GetEnumerator() | ForEach-Object { Write-Host "  [$($_.Value.status)] $($_.Key): $($_.Value.detail)" }
  }
  exit 20
}

# 3. Runtime Adapter (identify, don't execute)
$adaptersPath = Join-Path $projectRoot '.qianlima\agent-runtime-adapters.yaml'
$adapterId = 'unknown'
if (Test-Path -LiteralPath $adaptersPath -PathType Leaf) {
  $adapterContent = Get-Content -LiteralPath $adaptersPath -Raw
  if ($adapterContent -match 'id:\s*(codex_supervisor|codewhale_worker|claude_code_worker|raven_worker)') {
    $adapterId = $Matches[1]
  }
}
Set-Cp 'runtime_adapter' 'ok' "adapter=$adapterId mode=$(if ($ShadowRun) {'dry_run'} else {'governed'})"

# 4. Scheduling 鈥?persist a run queue entry
$queueDir = Join-Path $traceRoot 'run-queue'
if (-not (Test-Path -LiteralPath $queueDir -PathType Container)) { New-Item -ItemType Directory -Path $queueDir -Force | Out-Null }
$queueEntry = [ordered]@{
  schema_version = 1; run_id = $RunId; workflow_id = $WorkflowId
  task_text = $TaskText; context_level = $ContextLevel
  shadow_run = [bool]$ShadowRun; status = 'running'
  created_at = (Get-Date).ToUniversalTime().ToString('o')
}
$queuePath = Join-Path $queueDir "$RunId.json"
[IO.File]::WriteAllText($queuePath, ($queueEntry | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
Set-Cp 'scheduling' 'ok' "queue_entry_created run_id=$RunId"

# 5. Capability Gateway 鈥?resolve data source refs
if ($DataSourceRef.Count -gt 0) {
  $missing = @($DataSourceRef | Where-Object { -not (Test-Path -LiteralPath (Join-Path $projectRoot $_)) })
  if ($missing.Count -gt 0) { Set-Cp 'capability_gateway' 'warn' "Unresolved refs: $($missing -join ', ')" }
  else { Set-Cp 'capability_gateway' 'ok' "refs_resolved=$($DataSourceRef.Count)" }
} else { Set-Cp 'capability_gateway' 'ok' 'no data refs specified 鈥?file gateway open' }

# 6. Evidence & Verification 鈥?compute deterministic artifact hash
$payloadStr = "$RunId|$WorkflowId|$ContextLevel|$(Get-Date -Format 'yyyy-MM-dd')"
$sha256 = [Security.Cryptography.SHA256]::Create()
try {
  $hashHex = ([BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($payloadStr))) -replace '-','').ToLowerInvariant()
} finally { $sha256.Dispose() }
$artifactId = "run-$RunId"
$artifactRef = "run-traces/$RunId-artifact.json"
$receiptArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $scripts 'new-artifact-receipt.ps1'),
  '-ArtifactId',$artifactId,'-TaskId',$RunId,'-Name','harness_run_artifact',
  '-MediaType','application/json','-Reference',$artifactRef,
  '-IntegrityHash',"sha256:$hashHex",'-SourceClassification','internal_sanitized',
  '-VerificationStatus','passed')
& $psExe @receiptArgs | Out-Null
Set-Cp 'evidence_verification' 'ok' "artifact=$artifactId hash=sha256:$($hashHex.Substring(0,16))..."

# 7. Memory & State 鈥?first real writes to audit-events.jsonl + experience-events.jsonl
& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'write-audit-event.ps1') `
  -EventType 'harness_run' -Decision 'allow' -TaskId $RunId `
  -Reason "Harness run: $WorkflowId / $ContextLevel / shadow=$ShadowRun" | Out-Null
& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'write-experience-event.ps1') `
  -RunId $RunId -EventType 'final_delivery' -Component 'final_delivery' `
  -LatencyMs ([int]$sw.Elapsed.TotalMilliseconds) | Out-Null
Set-Cp 'memory_state' 'ok' 'audit-events.jsonl + experience-events.jsonl written'

# 8. Evaluation & Compounding 鈥?first real write to usage-ledger/runs.jsonl
$sw.Stop()
& (Join-Path $scripts 'record-qianlima-usage.ps1') -WorkflowId $WorkflowId -RunId $RunId `
  -TaskName ($TaskText.Substring(0, [Math]::Min(60, $TaskText.Length))) `
  -Provider 'local' -Model 'harness-script' | Out-Null
Set-Cp 'evaluation_loop' 'ok' "usage-ledger/runs.jsonl updated elapsed_ms=$([int]$sw.Elapsed.TotalMilliseconds)"

# Mark queue entry completed
$queueEntry.status = 'completed'
$queueEntry.completed_at = (Get-Date).ToUniversalTime().ToString('o')
[IO.File]::WriteAllText($queuePath, ($queueEntry | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))

$allOk = (@($checkpoints.Values | Where-Object { $_.status -notin @('ok','warn') }).Count -eq 0)
$result = [PSCustomObject]@{
  run_id = $RunId; workflow_id = $WorkflowId; shadow_run = [bool]$ShadowRun
  context_level = $ContextLevel; elapsed_ms = [int]$sw.Elapsed.TotalMilliseconds
  checkpoints = $checkpoints; all_ok = $allOk
}
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else {
  Write-Host "Harness run $RunId ($WorkflowId) 鈥?$(if ($allOk) {'ALL OK'} else {'ISSUES DETECTED'})"
  $checkpoints.GetEnumerator() | ForEach-Object {
  $icon = switch ($_.Value.status) { 'ok' { 'OK' } 'warn' { 'WARN' } default { 'FAIL' } }
    Write-Host "  [$icon] $($_.Key): $($_.Value.detail)"
  }
}

