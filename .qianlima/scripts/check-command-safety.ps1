<#
.SYNOPSIS
  Classify a shell command as allow, confirmation-required, or deny.
.DESCRIPTION
  Inspects a command string for destructive verbs, overwrite verbs and redirection,
  recursion, wildcards, variable paths, and parent traversal, then resolves literal target
  paths. Destructive and overwrite commands need an explicit in-workspace target, and
  recursive ops are limited to approved runtime scopes.
  Returns the classification and reasons; by default exits 10 for confirmation and 20 for deny.
.PARAMETER Command
  The full command string to evaluate.
.PARAMETER AsJson
  Emit the result object as JSON instead of console text.
.PARAMETER NoExit
  Do not set a non-zero exit code for confirmation or deny outcomes.
.EXAMPLE
  .\check-command-safety.ps1 -Command 'Remove-Item .\.qianlima\tmp\a.txt' -AsJson
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Command,
  [switch]$AsJson,
  [switch]$NoExit
)

$ErrorActionPreference = 'Stop'

function Test-PathWithin([string]$Candidate, [string]$Parent) {
  $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\')
  $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\')
  return $candidateFull.StartsWith($parentFull + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
    $candidateFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase)
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$allowedCleanupScopes = @(
  (Join-Path $projectRoot '.qianlima\tmp'),
  (Join-Path $projectRoot '.qianlima\logs'),
  (Join-Path $projectRoot '.qianlima\run-traces'),
  (Join-Path $projectRoot '.qianlima\reports\generated')
)
$reasons = New-Object System.Collections.Generic.List[string]
$lower = $Command.ToLowerInvariant()
# Deletion/move verbs, including PowerShell aliases (ri = Remove-Item, mi = Move-Item, ren/rni = Rename-Item).
$destructive = $lower -match '(^|[\s;|&`(])(remove-item|rm|ri|del|erase|rd|rmdir|clear-content|clc|format|format-volume|move-item|mi|mv|move|rename-item|ren|rni)([\s;|&`)]|$)'
# Overwrite verbs and redirection: a distinct high-risk class that the delete regex never covered.
# `>`/`>>` truncate or append to a file; `2>&1` and `>&` stream merges are excluded by requiring a non-&,>,| char after.
$overwrite = ($lower -match '(^|[\s;|&`(])(set-content|sc|out-file|tee-object|tee|add-content|ac)([\s;|&`)]|$)') -or
  ($Command -match '(^|\s)\d*>>?\s*[^\s&>|;]')
# PowerShell accepts any unambiguous prefix of -Recurse (-r, -rec, -recu, ...). Match all of them, plus cmd /s /q and -rf/-fr.
$recursive = $lower -match '(^|\s)-r(ecurse|ecurs|ecur|ecu|ec|e)?\b' -or $lower -match '(/s\b|/q\b|-rf\b|-fr\b)'
$hasWildcard = $Command -match '[*?]'
$hasVariablePath = $Command -match '(\$env:|\$home\b|\$userprofile\b|%userprofile%|%homepath%|%homedrive%)'
$hasTraversal = $Command -match '(^|[\\/])\.\.([\\/]|$)'

# Strip quoted spans first so the unquoted absolute-path regex cannot truncate a quoted path at its spaces.
$unquoted = [regex]::Replace($Command, '(["''])[^"'']*\1', ' ')
$absoluteMatches = [regex]::Matches($unquoted, '(?i)[a-z]:\\[^\s"''|;&]*') | ForEach-Object { $_.Value.Trim('"', '''', ',', ')', ']') }
$quotedMatches = [regex]::Matches($Command, '(["''])(?<path>[^"'']+)\1') | ForEach-Object { $_.Groups['path'].Value }
$targets = @(@($absoluteMatches) + @($quotedMatches))
$targets = @($targets | Where-Object { $_ -and ($_ -notmatch '^[-/]') } | Sort-Object -Unique)

$classification = 'allow'
if ($destructive -or $overwrite) {
  $classification = 'confirmation_required'
  if ($hasVariablePath) { $reasons.Add('Variable-based target path is not allowed for destructive commands.') }
  if ($hasWildcard) { $reasons.Add('Wildcard target is not allowed for destructive commands.') }
  if ($hasTraversal) { $reasons.Add('Parent-directory traversal is not allowed for destructive commands.') }
  if ($targets.Count -eq 0) { $reasons.Add('Destructive command needs an explicit literal target path.') }

  foreach ($target in $targets) {
    $candidate = if ([System.IO.Path]::IsPathRooted($target)) { $target } else { Join-Path $projectRoot $target }
    try {
      $resolved = [System.IO.Path]::GetFullPath($candidate)
    } catch {
      $reasons.Add("Target path cannot be resolved: $target")
      continue
    }
    if ($resolved -match '^[A-Za-z]:\\?$') {
      $reasons.Add("Disk root is forbidden: $resolved")
      continue
    }
    if (-not (Test-PathWithin $resolved $projectRoot)) {
      $reasons.Add("Target is outside the workspace: $resolved")
      continue
    }
    if ($recursive -and -not (@($allowedCleanupScopes | Where-Object { Test-PathWithin $resolved $_ }).Count -gt 0)) {
      $reasons.Add("Recursive operation is limited to approved runtime scopes: $resolved")
    }
  }
  if ($reasons.Count -gt 0) { $classification = 'deny' }
}

$result = [PSCustomObject]@{
  classification = $classification
  destructive = $destructive
  overwrite = $overwrite
  recursive = $recursive
  targets = $targets
  workspace = $projectRoot
  allowed_cleanup_scopes = $allowedCleanupScopes
  reasons = @($reasons)
  required_action = switch ($classification) {
    'allow' { 'may_continue' }
    'confirmation_required' { 'show_absolute_targets_and_wait_for_explicit_second_confirmation' }
    'deny' { 'do_not_execute' }
  }
}

if ($AsJson) {
  $result | ConvertTo-Json -Depth 5
} else {
  Write-Host "Command safety: $($result.classification)"
  foreach ($reason in $result.reasons) { Write-Host "- $reason" }
}

if (-not $NoExit) {
  if ($classification -eq 'confirmation_required') { exit 10 }
  if ($classification -eq 'deny') { exit 20 }
}
