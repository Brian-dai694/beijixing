<# .SYNOPSIS Verifies the Personal Edition manifest and shared-core boundary. #>
param([switch]$PassThru)
$ErrorActionPreference='Stop';$personalRoot=$PSScriptRoot;$repoRoot=(Resolve-Path(Join-Path $personalRoot '..\..')).Path;$editionPath=Join-Path $personalRoot 'edition.yaml';$configPath=Join-Path $personalRoot 'config.example.yaml';$cases=[System.Collections.Generic.List[object]]::new();function Add($n,$p){$cases.Add([pscustomobject]@{name=$n;passed=[bool]$p})};$edition=Get-Content -LiteralPath $editionPath -Raw -Encoding UTF8;$config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
Add 'personal_manifest_is_explicit' ($edition-match'(?m)^\s*id:\s*personal\s*$'-and$edition-match'(?m)^\s*product_profile:\s*personal-local-first\s*$')
Add 'personal_references_shared_core' ($edition-match'(?m)^\s*shared_core_root:\s*\.\./\.\.\s*$'-and(Test-Path(Join-Path $repoRoot '.qianlima\CODEX_BOOT.md')))
Add 'personal_does_not_fork_harness' ($edition-match'(?m)^\s*do_not_fork_harness:\s*true\s*$'-and-not(Test-Path(Join-Path $personalRoot '.qianlima')))
Add 'personal_preferences_are_user_controlled' ($config-match'(?m)^\s*user_visible:\s*true\s*$'-and$config-match'(?m)^\s*user_editable:\s*true\s*$'-and$config-match'(?m)^\s*user_deletable:\s*true\s*$')
Add 'personal_permissions_do_not_auto_expand' ($edition-match'(?m)^\s*automatic_permission_expansion:\s*false\s*$')
Add 'personal_background_tasks_default_off' ($edition-match'(?m)^\s*background_tasks:\s*disabled_until_user_starts\s*$')
Add 'personal_defaults_to_single_agent' ($edition-match'(?m)^\s*collaboration_default:\s*single_agent\s*$'-and$edition-match'(?m)^\s*delegation:\s*only_for_independent_goal_evidence_or_review\s*$')
Add 'enterprise_scale_services_not_loaded_in_personal' ($edition-match'(?m)^\s*enterprise_queue_and_multi_tenant_services:\s*not_loaded\s*$'-and$edition-notmatch'enterprise-collaboration-scale-contract')
$failed=@($cases|?{-not$_.passed});$r=[pscustomobject]@{passed=($failed.Count-eq0);edition='personal';shared_core_unchanged=$true;external_calls=$false;cases=$cases};if($PassThru){$r|ConvertTo-Json -Depth 8}else{$cases|Format-Table -AutoSize};if($failed.Count){throw('Personal profile failed: '+(($failed.name)-join', '))}
