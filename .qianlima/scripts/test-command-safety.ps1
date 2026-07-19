$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$guardScript = Join-Path $PSScriptRoot 'check-command-safety.ps1'
$cases = @(
  [PSCustomObject]@{ Name = 'read_only'; Command = 'Get-Content .qianlima\CODEX_BOOT.md'; Expected = 'allow' },
  [PSCustomObject]@{ Name = 'controlled_cleanup'; Command = 'Remove-Item -LiteralPath ''.qianlima\tmp\old.txt'''; Expected = 'confirmation_required' },
  [PSCustomObject]@{ Name = 'rm_recursive_root'; Command = 'rm -rf C:\'; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'remove_item_recursive_user_root'; Command = 'Remove-Item -Recurse -Force ''C:\Users\example-user'''; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'del_batch'; Command = 'del /f /s /q ''C:\OutsideWorkspace\*'''; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'rd_batch'; Command = 'rd /s /q ''D:\'''; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'home_variable'; Command = 'Remove-Item -Recurse $HOME'; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'userprofile_variable'; Command = 'Remove-Item -Recurse %USERPROFILE%'; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'wildcard_target'; Command = 'Remove-Item ''.qianlima\tmp\*'''; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'parent_traversal'; Command = 'Clear-Content -LiteralPath ''..\notes.md'''; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'move_outside_workspace'; Command = 'Move-Item ''.qianlima\tmp\file.txt'' ''C:\OutsideWorkspace\file.txt'''; Expected = 'deny' },
  # Regression: alias, redirection, overwrite-verb, and recurse-abbreviation bypasses.
  [PSCustomObject]@{ Name = 'ri_alias_recursive_outside'; Command = 'ri -Recurse ''C:\Windows'''; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'redirect_overwrite_outside'; Command = 'Get-Process > ''C:\important.txt'''; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'set_content_overwrite_outside'; Command = 'Set-Content ''C:\boot.ini'' -Value x'; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'out_file_overwrite_outside'; Command = 'Out-File -FilePath ''C:\OutsideWorkspace\x.txt'''; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'recurse_abbrev_nonscope'; Command = 'Remove-Item ''.qianlima\config'' -rec'; Expected = 'deny' },
  [PSCustomObject]@{ Name = 'stream_merge_not_overwrite'; Command = 'Get-Content .qianlima\CODEX_BOOT.md 2>&1'; Expected = 'allow' },
  [PSCustomObject]@{ Name = 'in_workspace_overwrite'; Command = 'Set-Content ''.qianlima\reports\generated\out.md'' -Value x'; Expected = 'confirmation_required' }
)

$results = foreach ($case in $cases) {
  $result = & $guardScript -Command $case.Command -AsJson -NoExit | ConvertFrom-Json
  [PSCustomObject]@{
    name = $case.Name
    expected = $case.Expected
    actual = $result.classification
    passed = $result.classification -eq $case.Expected
  }
}

$failed = @($results | Where-Object { -not $_.passed })
$results | Format-Table -AutoSize
if ($failed.Count -gt 0) {
  throw "Command safety regression failed: $($failed.name -join ', ')"
}
Write-Host "Command safety regression passed: $($results.Count) cases."
