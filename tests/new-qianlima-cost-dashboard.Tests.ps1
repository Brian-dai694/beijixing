BeforeAll {
  $script:ScriptPath = Join-Path $PSScriptRoot '..\.qianlima\scripts\new-qianlima-cost-dashboard.ps1'
  $script:TmpDir = Join-Path $env:TEMP ('cost-dashboard-' + [guid]::NewGuid().ToString('N'))
  $script:LedgerPath = Join-Path $script:TmpDir 'runs.jsonl'
  $script:BaselinePath = Join-Path $script:TmpDir 'baselines.json'
  $script:OutputPath = Join-Path $script:TmpDir 'dashboard.md'
  New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
}

AfterAll { Remove-Item -LiteralPath $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'new-qianlima-cost-dashboard currency handling' {
  It 'keeps USD and CNY costs in separate totals and applies only same-currency baselines' {
    $now = (Get-Date).ToUniversalTime().ToString('o')
    @(
      @{ schema_version = 2; run_id = 'usd'; workflow_id = 'cost_test'; status = 'completed'; recorded_at = $now; currency = 'USD'; estimated_cost = 1; model_cost = 0.8; tool_cost = 0.2 },
      @{ schema_version = 2; run_id = 'cny'; workflow_id = 'cost_test'; status = 'completed'; recorded_at = $now; currency = 'CNY'; estimated_cost = 7; model_cost = 7; tool_cost = 0 }
    ) | ForEach-Object { $_ | ConvertTo-Json -Compress | Add-Content -LiteralPath $script:LedgerPath -Encoding UTF8 }
    @{ schema_version = 2; workflows = @{ cost_test = @{ currencies = @{ USD = @{ currency = 'USD'; baseline_cost = 0.5 }; CNY = @{ currency = 'CNY'; baseline_cost = 5 } } } } } |
      ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:BaselinePath -Encoding UTF8

    & $script:ScriptPath -Days 1 -LedgerPath $script:LedgerPath -BaselinePath $script:BaselinePath -OutputPath $script:OutputPath | Out-Null
    $dashboard = Get-Content -LiteralPath $script:OutputPath -Raw -Encoding UTF8

    $dashboard | Should -Match '\| USD \| 1 \| USD 1\.000000 \| USD 1\.000000 \|'
    $dashboard | Should -Match '\| CNY \| 1 \| CNY 7\.000000 \| CNY 7\.000000 \|'
    $dashboard | Should -Match '\| cost_test \| USD \| 1 \| USD 1\.000000 \| USD 0\.500000 \| 0 \|'
    $dashboard | Should -Match '\| cost_test \| CNY \| 1 \| CNY 7\.000000 \| CNY 5\.000000 \| 0 \|'
    $dashboard | Should -Match 'Amounts are intentionally not totaled across currencies'
  }
}
