BeforeAll {
  $script:RecordScript = Join-Path $PSScriptRoot '..\.qianlima\scripts\record-qianlima-usage.ps1'
  $script:ModulePath = Join-Path $PSScriptRoot '..\.qianlima\scripts\Qianlima.UsageLedger.psm1'
  $script:TmpDir = Join-Path $env:TEMP ('canonical-ledger-' + [guid]::NewGuid().ToString('N'))
  $script:LedgerPath = Join-Path $script:TmpDir 'usage-ledger\runs.jsonl'
  New-Item -ItemType Directory -Path (Split-Path -Parent $script:LedgerPath) -Force | Out-Null
  Import-Module $script:ModulePath -Force
}

AfterAll { Remove-Item -LiteralPath $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'record-qianlima-usage canonical ledger' {
  It 'writes schema v2 with tokenizer provenance and a currency-safe cost split' {
    $result = & $script:RecordScript -WorkflowId cost_test -RunId v2-record -InputTokens 100 -OutputTokens 25 `
      -CacheHitTokens 20 -ReasoningTokens 10 -EstimatedInputTokens 80 -EstimatedOutputTokens 20 `
      -TokenizerId o200k_base -TokenizerVersion 2026-07 -WorkloadType typescript `
      -TokenMeasurementMethod local_encoder -TokenMeasurementReference fixture `
      -EstimatedCost 1 -ToolCost 0.2 -Currency USD -BilledCost 1.01 -PassThru -LedgerPath $script:LedgerPath

    $result.Record.schema_version | Should -Be 2
    $result.Record.currency | Should -Be 'USD'
    $result.Record.model_cost | Should -Be 0.8
    $result.Record.tool_cost | Should -Be 0.2
    $result.Record.input_token_delta | Should -Be 20
    $result.Record.total_token_delta_pct | Should -Be 25
    $result.Record.billing_status | Should -Be 'within_tolerance'
  }

  It 'reads legacy schema v1 records as USD without assigning USD to schema v2 CNY data' {
    '{"schema_version":1,"run_id":"legacy","workflow_id":"cost_test","estimated_cost_usd":3,"status":"completed","recorded_at":"2026-07-19T00:00:00Z"}' |
      Add-Content -LiteralPath $script:LedgerPath -Encoding UTF8
    & $script:RecordScript -WorkflowId cost_test -RunId cny-record -EstimatedCost 3 -Currency CNY -PassThru -LedgerPath $script:LedgerPath | Out-Null

    $records = @(Get-QianlimaUsageLedgerRecords -LedgerPath $script:LedgerPath)
    (@($records | Where-Object run_id -eq 'legacy')[0]).currency | Should -Be 'USD'
    (@($records | Where-Object run_id -eq 'cny-record')[0]).currency | Should -Be 'CNY'
  }

  It 'rejects invalid token breakdowns and mismatched money currencies' {
    { & $script:RecordScript -WorkflowId cost_test -RunId invalid-cache -InputTokens 1 -CacheHitTokens 2 -LedgerPath $script:LedgerPath } | Should -Throw
    { & $script:RecordScript -WorkflowId cost_test -RunId invalid-reasoning -OutputTokens 1 -ReasoningTokens 2 -LedgerPath $script:LedgerPath } | Should -Throw
    { & $script:RecordScript -WorkflowId cost_test -RunId invalid-currency -EstimatedCost 1 -ToolCost 0.1 -Currency USD -ToolCostCurrency CNY -LedgerPath $script:LedgerPath } | Should -Throw
  }

  It 'refuses duplicate run identifiers in the append-only ledger' {
    { & $script:RecordScript -WorkflowId cost_test -RunId v2-record -LedgerPath $script:LedgerPath } | Should -Throw
  }
}
