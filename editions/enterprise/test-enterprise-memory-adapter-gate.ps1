param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$gate = Join-Path $PSScriptRoot 'invoke-enterprise-memory-adapter-gate.ps1'
$registry = Join-Path $PSScriptRoot 'memory-adapter-registry.example.json'

function RunGate([string[]]$Arguments) {
  $raw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate @Arguments 2>&1)
  [pscustomobject]@{
    code = $LASTEXITCODE
    text = (($raw | ForEach-Object { $_.ToString() }) -join "`n")
  }
}

$cases = [System.Collections.Generic.List[object]]::new()
$disabled = RunGate @(
  '-RegistryPath', $registry,
  '-AdapterId', 'local_sqlite_fts5',
  '-Operation', 'query',
  '-ExpectedManifestHash', 'sha256:replace-with-reviewed-manifest-hash',
  '-AttestationStatus', 'verified',
  '-PassThru'
)
$cases.Add([pscustomobject]@{
    name = 'disabled_sqlite_adapter_is_blocked'
    passed = ($disabled.code -ne 0 -and $disabled.text -match 'adapter_disabled')
})

$unknown = RunGate @(
  '-RegistryPath', $registry,
  '-AdapterId', 'unknown',
  '-Operation', 'query',
  '-ExpectedManifestHash', 'sha256:none',
  '-AttestationStatus', 'verified',
  '-PassThru'
)
$cases.Add([pscustomobject]@{
    name = 'unknown_adapter_is_blocked'
    passed = ($unknown.code -ne 0 -and $unknown.text -match 'adapter_not_registered')
})

$stale = RunGate @(
  '-RegistryPath', $registry,
  '-AdapterId', 'local_sqlite_fts5',
  '-Operation', 'query',
  '-ExpectedManifestHash', 'sha256:wrong',
  '-AttestationStatus', 'verified',
  '-PassThru'
)
$cases.Add([pscustomobject]@{
  name = 'disabled_adapter_blocks_before_manifest_use'
  passed = ($stale.code -ne 0 -and $stale.text -match 'adapter_disabled')
})

$failed = @($cases | Where-Object { -not $_.passed })
$out = [pscustomobject]@{
  passed = ($failed.Count -eq 0)
  cases = @($cases)
  adapter_started = $false
  listeners_opened = $false
  external_calls = $false
}
if ($PassThru) { $out | ConvertTo-Json -Depth 10 } else { $cases | Format-Table -AutoSize }
if ($failed.Count) { throw ('Enterprise memory adapter gate regression failed: ' + (($failed.name) -join ', ')) }
