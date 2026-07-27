param(
  [Parameter(Mandatory = $true)][string]$RegistryPath,
  [Parameter(Mandatory = $true)][string]$AdapterId,
  [Parameter(Mandatory = $true)][ValidateSet('index', 'query', 'health')][string]$Operation,
  [Parameter(Mandatory = $true)][string]$ExpectedManifestHash,
  [Parameter(Mandatory = $true)][ValidateSet('missing', 'verified', 'expired', 'revoked')][string]$AttestationStatus,
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$registryRoot = [IO.Path]::GetFullPath($PSScriptRoot) + [IO.Path]::DirectorySeparatorChar

function Emit([object]$Value, [int]$Code = 0) {
  if ($PassThru) { $Value | ConvertTo-Json -Depth 10 } else { $Value | Format-List }
  if ($Code -ne 0) { exit $Code }
}

try {
  $full = (Resolve-Path -LiteralPath $RegistryPath -ErrorAction Stop).Path
  $registry = Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  $blocked = [ordered]@{ status = 'blocked'; reason = 'adapter_registry_invalid'; adapter_started = $false; external_calls = $false }
  Emit $blocked 1
}

if (-not $full.StartsWith($registryRoot, [StringComparison]::OrdinalIgnoreCase)) {
  $blocked = [ordered]@{ status = 'blocked'; reason = 'adapter_registry_outside_enterprise_root'; adapter_started = $false; external_calls = $false }
  Emit $blocked 1
}

$adapter = @($registry.adapters | Where-Object { $_.adapter_id -eq $AdapterId }) | Select-Object -First 1
if ($null -eq $adapter) {
  $blocked = [ordered]@{ status = 'blocked'; reason = 'adapter_not_registered'; adapter_started = $false; external_calls = $false }
  Emit $blocked 1
}

$reasons = [System.Collections.Generic.List[string]]::new()
function Deny([string]$Id) { [void]$reasons.Add($Id) }
if ($registry.default_enabled -eq $true) { Deny 'registry_default_enable_must_be_false' }
if ($adapter.enabled -ne $true) { Deny 'adapter_disabled' }
if ($adapter.execution_enabled -ne $true) { Deny 'adapter_execution_disabled' }
if ([string]$adapter.manifest_hash -ne $ExpectedManifestHash) { Deny 'adapter_manifest_drift' }
if ($AttestationStatus -ne 'verified') { Deny 'verified_adapter_attestation_required' }
if ([string]$adapter.network -ne 'none') { Deny 'adapter_network_must_be_none' }
if ($reasons.Count) {
  $blocked = [ordered]@{ status = 'blocked'; adapter_id = $AdapterId; operation = $Operation; reasons = @($reasons); adapter_started = $false; external_calls = $false; listeners_opened = $false }
  Emit $blocked 1
}

$allowed = [ordered]@{ status = 'allowed'; adapter_id = $AdapterId; operation = $Operation; adapter_started = $false; execution_authorized = $true; external_calls = $false; listeners_opened = $false; requires_task_grant = $true }
Emit $allowed
