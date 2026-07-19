BeforeAll {
  $script:ScriptPath = Join-Path $PSScriptRoot '..\.qianlima\scripts\compare-model-effective-cost.ps1'
  $script:TmpDir = Join-Path $env:TEMP ("effective-cost-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
  $script:CatalogPath = Join-Path $script:TmpDir 'catalog.json'
  $script:MeasurementsPath = Join-Path $script:TmpDir 'measurements.json'
  @{
    catalog_version = 'test'
    models = @(
      @{ provider = 'alpha'; model = 'a'; currency = 'USD'; source_url = 'https://example.test/a'; pricing_per_million_tokens = @{ input = 1; cached_input = 0.1; output = 2 } },
      @{ provider = 'beta'; model = 'b'; currency = 'USD'; source_url = 'https://example.test/b'; pricing_per_million_tokens = @{ input = 2; cached_input = 0.2; output = 2 } },
      @{ provider = 'gamma'; model = 'c'; currency = 'CNY'; source_url = 'https://example.test/c'; pricing_per_million_tokens = @{ input = 1; cached_input = 0.1; output = 2 } }
    )
    source_only_providers = @(@{ provider = 'unknown'; source_url = 'https://example.test/unknown' })
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:CatalogPath -Encoding UTF8
}

AfterAll {
  Remove-Item -LiteralPath $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'compare-model-effective-cost' {
  It 'prices target-model measurements and ranks only within the same currency' {
    @{
      workload_type = 'typescript'
      models = @(
        @{ provider = 'alpha'; model = 'a'; input_tokens = 1000000; output_tokens = 1000000; cached_input_tokens = 0; reasoning_tokens = 0; tokenizer_id = 'alpha-tokenizer'; tokenizer_version = '1'; measurement_method = 'official_counter'; measurement_reference = 'test' },
        @{ provider = 'beta'; model = 'b'; input_tokens = 1000000; output_tokens = 1000000; cached_input_tokens = 0; reasoning_tokens = 0; tokenizer_id = 'beta-tokenizer'; tokenizer_version = '2'; measurement_method = 'provider_usage'; measurement_reference = 'test' },
        @{ provider = 'gamma'; model = 'c'; input_tokens = 1000000; output_tokens = 1000000; cached_input_tokens = 0; reasoning_tokens = 0; tokenizer_id = 'gamma-tokenizer'; tokenizer_version = '1'; measurement_method = 'local_encoder'; measurement_reference = 'test' }
      )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:MeasurementsPath -Encoding UTF8

    $r = & $script:ScriptPath -MeasurementsPath $script:MeasurementsPath -CatalogPath $script:CatalogPath -AsJson | ConvertFrom-Json
    $alpha = @($r.records | Where-Object { $_.provider -eq 'alpha' })[0]
    $beta = @($r.records | Where-Object { $_.provider -eq 'beta' })[0]
    $gamma = @($r.records | Where-Object { $_.provider -eq 'gamma' })[0]
    $alpha.effective_cost | Should -Be 3
    $beta.effective_cost | Should -Be 4
    $alpha.rank_within_currency | Should -Be 1
    $beta.rank_within_currency | Should -Be 2
    $gamma.rank_within_currency | Should -Be 1
    $alpha.workload_type | Should -Be 'typescript'
    $alpha.tokenizer_id | Should -Be 'alpha-tokenizer'
  }

  It 'marks unverified prices source_only without inventing a cost' {
    @{ workload_type = 'prompt'; models = @(@{ provider = 'unknown'; model = 'x'; input_tokens = 100; output_tokens = 10; tokenizer_id = 'unknown'; tokenizer_version = 'unknown'; measurement_method = 'estimate'; measurement_reference = 'test' }) } |
      ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:MeasurementsPath -Encoding UTF8

    $r = & $script:ScriptPath -MeasurementsPath $script:MeasurementsPath -CatalogPath $script:CatalogPath -AsJson | ConvertFrom-Json
    $r.records[0].status | Should -Be 'source_only'
    $r.records[0].effective_cost | Should -BeNullOrEmpty
    $r.records[0].rank_within_currency | Should -BeNullOrEmpty
  }

  It 'rejects cached input larger than target-model input' {
    @{ workload_type = 'json'; models = @(@{ provider = 'alpha'; model = 'a'; input_tokens = 10; output_tokens = 1; cached_input_tokens = 11; tokenizer_id = 'alpha'; tokenizer_version = '1'; measurement_method = 'official_counter'; measurement_reference = 'test' }) } |
      ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:MeasurementsPath -Encoding UTF8

    { & $script:ScriptPath -MeasurementsPath $script:MeasurementsPath -CatalogPath $script:CatalogPath -AsJson } | Should -Throw
  }

  It 'rejects a non-zero tool cost in a different currency from the model price' {
    @{ workload_type = 'typescript'; models = @(@{ provider = 'alpha'; model = 'a'; input_tokens = 10; output_tokens = 1; tokenizer_id = 'alpha'; tokenizer_version = '1'; measurement_method = 'official_counter'; measurement_reference = 'test'; tool_cost = 0.1; tool_cost_currency = 'CNY' }) } |
      ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:MeasurementsPath -Encoding UTF8

    { & $script:ScriptPath -MeasurementsPath $script:MeasurementsPath -CatalogPath $script:CatalogPath -AsJson } | Should -Throw
  }

}
