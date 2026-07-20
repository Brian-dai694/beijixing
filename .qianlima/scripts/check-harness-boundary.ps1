<##
.SYNOPSIS
  Verifies that the core Harness has not changed since the reviewed baseline.
.DESCRIPTION
  This is an Overlay-side guard. It does not modify core Harness files. A
  candidate path may be checked before a governance edit; only explicit
  Overlay paths are allowed.
##>
param(
  [string]$CandidatePath = '',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$manifestPath = Join-Path $projectRoot '.qianlima\harness-boundary.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$violations = [System.Collections.Generic.List[string]]::new()
function Get-CanonicalTextHash([string]$Path) {
  $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false))
  $normalized = $text.Replace("`r`n", "`n").Replace("`r", "`n")
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($normalized)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}
foreach ($entry in @($manifest.protected_files)) {
  $fullPath = Join-Path $projectRoot ($entry.path -replace '/', '\')
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { [void]$violations.Add("missing:$($entry.path)"); continue }
  $actual = Get-CanonicalTextHash $fullPath
  if ($actual -ne $entry.sha256) { [void]$violations.Add("changed:$($entry.path)") }
}
if ($CandidatePath) {
  $candidateRelative = $CandidatePath
  if ([IO.Path]::IsPathRooted($CandidatePath)) { $candidateRelative = $CandidatePath.Substring($projectRoot.Length).TrimStart('\', '/') }
  $candidateRelative = $candidateRelative -replace '\\', '/'
  $protectedMatch = @($manifest.protected_files | Where-Object { $_.path -eq $candidateRelative }).Count -gt 0
  $overlayMatch = $false
  foreach ($allowed in @($manifest.allowed_overlay_roots)) {
    $pattern = '^' + [regex]::Escape($allowed).Replace('\*', '.*') + '$'
    if ($candidateRelative -match $pattern) { $overlayMatch = $true; break }
  }
  if ($protectedMatch) { [void]$violations.Add("candidate_core_protected:$candidateRelative") }
  elseif (-not $overlayMatch) { [void]$violations.Add("candidate_outside_overlay:$candidateRelative") }
}
$result = [ordered]@{ status = if ($violations.Count -eq 0) { 'pass' } else { 'blocked' }; boundary_id = $manifest.boundary_id; core_read_only = $true; violations = @($violations); candidate = if ($CandidatePath) { $CandidatePath } else { $null }; checked_at = (Get-Date).ToUniversalTime().ToString('o') }
if ($PassThru) { $result | ConvertTo-Json -Depth 8 } else { $result | Format-List }
if ($violations.Count -gt 0) { exit 1 }
