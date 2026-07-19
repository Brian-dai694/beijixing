BeforeAll {
  $script:ScriptPath = Join-Path $PSScriptRoot '..\.qianlima\scripts\set-qianlima-cost-baseline.ps1'
  $script:TmpDir = Join-Path $env:TEMP ('cost-baseline-' + [guid]::NewGuid().ToString('N'))
  $script:LedgerPath = Join-Path $script:TmpDir 'runs.jsonl'
  $script:BaselinePath = Join-Path $script:TmpDir 'baselines.json'
  New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
  $records = @()
  foreach ($cost in @(1, 2, 3)) { $records += @{ schema_version = 2; run_id = "usd-$cost"; workflow_id = 'cost_test'; status = 'completed'; recorded_at = '2026-07-19T00:00:00Z'; currency = 'USD'; estimated_cost = $cost; model_cost = $cost; tool_cost = 0 } }
  foreach ($cost in @(6, 7, 8)) { $records += @{ schema_version = 2; run_id = "cny-$cost"; workflow_id = 'cost_test'; status = 'completed'; recorded_at = '2026-07-19T00:00:00Z'; currency = 'CNY'; estimated_cost = $cost; model_cost = $cost; tool_cost = 0 } }
  $records | ForEach-Object { $_ | ConvertTo-Json -Compress | Add-Content -LiteralPath $script:LedgerPath -Encoding UTF8 }
}

AfterAll { Remove-Item -LiteralPath $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'set-qianlima-cost-baseline currency handling' {
  It 'requires a currency when completed workflow runs contain multiple currencies' {
    { & $script:ScriptPath -WorkflowId cost_test -SampleSize 3 -LedgerPath $script:LedgerPath -BaselinePath $script:BaselinePath } | Should -Throw
  }

  It 'stores median baselines by workflow and currency' {
    & $script:ScriptPath -WorkflowId cost_test -Currency USD -SampleSize 3 -LedgerPath $script:LedgerPath -BaselinePath $script:BaselinePath | Out-Null
    & $script:ScriptPath -WorkflowId cost_test -Currency CNY -SampleSize 3 -LedgerPath $script:LedgerPath -BaselinePath $script:BaselinePath | Out-Null
    $document = Get-Content -LiteralPath $script:BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json

    $document.schema_version | Should -Be 2
    $document.workflows.cost_test.currencies.USD.baseline_cost | Should -Be 2
    $document.workflows.cost_test.currencies.CNY.baseline_cost | Should -Be 7
  }
}
