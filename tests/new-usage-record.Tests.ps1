BeforeAll {
  $script:ScriptPath = Join-Path $PSScriptRoot '..\.qianlima\scripts\new-usage-record.ps1'
  $script:TmpDir = Join-Path $env:TEMP ("usagepester-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
  function script:Make { param($p) & $script:ScriptPath -Root $script:TmpDir @p | Out-Null }
  function script:Ledger { param($runId)
    $safe = $runId -replace '[^A-Za-z0-9_.-]', '-'
    Get-Content -LiteralPath (Join-Path $script:TmpDir "usage-ledger\$safe.yaml") -Raw
  }
  function script:CanonicalLedger {
    Get-Content -LiteralPath (Join-Path $script:TmpDir 'usage-ledger\runs.jsonl') -Raw
  }
}

AfterAll { Remove-Item -Recurse -Force $script:TmpDir -ErrorAction SilentlyContinue }

Describe 'new-usage-record cost guard' {
  It 'flags over_limit and needs_confirmation when cost exceeds the limit' {
    Make @{ RunId = 'overlimit'; EstimatedCost = 5; CostLimit = 1; Force = $true }
    $y = Ledger 'overlimit'
    $y | Should -Match 'cost_status: over_limit'
    $y | Should -Match 'continue_or_stop: needs_confirmation'
  }
  It 'flags over_baseline_guard when cost exceeds 2x baseline' {
    Make @{ RunId = 'baseguard'; EstimatedCost = 3; BaselineCost = 1; Force = $true }
    Ledger 'baseguard' | Should -Match 'cost_status: over_baseline_guard'
  }
  It 'prioritizes over_limit over the baseline guard' {
    Make @{ RunId = 'prec'; EstimatedCost = 5; CostLimit = 1; BaselineCost = 1; Force = $true }
    Ledger 'prec' | Should -Match 'cost_status: over_limit'
  }
  It 'stays continue and computes savings for a normal run' {
    Make @{ RunId = 'normal'; EstimatedCost = 1; BaselineCost = 10; Force = $true }
    $y = Ledger 'normal'
    $y | Should -Match 'continue_or_stop: continue'
    $y | Should -Match 'estimated_savings: 9'
  }
  It 'sanitizes the run id into the file name' {
    Make @{ RunId = 'a/b c'; EstimatedCost = 1; Force = $true }
    Test-Path (Join-Path $script:TmpDir 'usage-ledger\a-b-c.yaml') | Should -BeTrue
  }
  It 'records tokenizer provenance and measured-versus-estimated token variance' {
    Make @{ RunId = 'token-variance'; InputTokens = 1730; OutputTokens = 200; EstimatedInputTokens = 1000; EstimatedOutputTokens = 200; TokenizerId = 'official-counter'; TokenizerVersion = '2026-07'; WorkloadType = 'typescript'; TokenMeasurementMethod = 'official_counter'; TokenMeasurementReference = 'https://example.test/count'; Force = $true }
    $y = Ledger 'token-variance'
    $y | Should -Match "id: 'official-counter'"
    $y | Should -Match 'workload_type: ''typescript'''
    $y | Should -Match 'input_tokens_delta: 730'
    $y | Should -Match 'total_tokens_delta_pct: 60.83'
  }
  It 'flags billed cost variance outside the configured tolerance' {
    Make @{ RunId = 'billing-variance'; EstimatedCost = 1; BilledCost = 1.1; BillingTolerancePct = 1; Force = $true }
    $y = Ledger 'billing-variance'
    $y | Should -Match 'status: variance_detected'
    $y | Should -Match 'estimated_cost_delta_pct: 10'
  }
  It 'includes tool cost in the effective estimated cost' {
    Make @{ RunId = 'tool-cost'; EstimatedCost = 1; ToolCost = 0.25; Force = $true }
    $y = Ledger 'tool-cost'
    $y | Should -Match 'estimated_cost: 1'
    $y | Should -Match 'model_cost: 0.75'
    $y | Should -Match 'tool_cost: 0.25'
  }
  It 'appends the YAML evidence to the canonical versioned JSONL ledger' {
    Make @{ RunId = 'canonical'; TaskSuccess = $true; InputTokens = 10; OutputTokens = 2; EstimatedCost = 0.1; Currency = 'CNY'; Force = $true }
    $record = @(CanonicalLedger -split "`r?`n" | Where-Object { $_ -match '"run_id":"canonical"' })[0]
    $record | Should -Not -BeNullOrEmpty
    $record | Should -Match '"schema_version":2'
    $record | Should -Match '"run_id":"canonical"'
    $record | Should -Match '"currency":"CNY"'
    $record | Should -Match '"estimated_cost":0\.1(?:,|\})'
  }
  It 'rejects cached input or reasoning tokens outside the declared totals' {
    { & $script:ScriptPath -Root $script:TmpDir -RunId 'bad-cache' -InputTokens 1 -CachedInputTokens 2 -Force } | Should -Throw
    { & $script:ScriptPath -Root $script:TmpDir -RunId 'bad-reasoning' -OutputTokens 1 -ReasoningTokens 2 -Force } | Should -Throw
  }
  It 'rejects a tool cost larger than the total effective cost' {
    { & $script:ScriptPath -Root $script:TmpDir -RunId 'invalid-tool-cost' -EstimatedCost 0.1 -ToolCost 0.2 -Force } | Should -Throw
  }
  It 'throws on negative cost' {
    { & $script:ScriptPath -Root $script:TmpDir -RunId 'neg' -EstimatedCost -1 -Force } | Should -Throw
  }
  It 'throws when the ledger exists and -Force is absent' {
    Make @{ RunId = 'dup'; EstimatedCost = 1; Force = $true }
    { & $script:ScriptPath -Root $script:TmpDir -RunId 'dup' -EstimatedCost 1 } | Should -Throw
  }

}
