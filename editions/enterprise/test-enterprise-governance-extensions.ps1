[CmdletBinding()]
param(
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$enterpriseRoot = $PSScriptRoot
$projectRoot = (Resolve-Path (Join-Path $enterpriseRoot '..\..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) {
        $script:failures.Add("$Name expected '$Expected' but got '$Actual'.")
    }
}

function Assert-Contains {
    param([string]$Name, [object[]]$Collection, [string]$Expected)
    if ($Collection -notcontains $Expected) {
        $script:failures.Add("$Name must contain '$Expected'.")
    }
}

function Read-Policy {
    param([string]$RelativePath)
    Get-Content -LiteralPath (Join-Path $enterpriseRoot $RelativePath) -Raw -Encoding UTF8 | ConvertFrom-Json
}

$memory = Read-Policy 'enterprise-memory-os-policy.json'
Assert-Equal 'Memory OS positioning' $memory.positioning 'memory_and_skill_subsystem_reference_not_enterprise_governance_authority'
Assert-Equal 'Memory cross-organization default' $memory.cube.cross_organization_default 'deny'
Assert-Equal 'Memory scope filter order' $memory.retrieval.mandatory_order[1] 'cube_scope_filter'
Assert-Equal 'Memory similarity boundary' $memory.retrieval.similarity_never_bypasses_scope $true
Assert-Equal 'Skill memory execution authority' $memory.skill_boundary.skill_memory_grants_execution $false
Assert-Equal 'Skill memory tool authority' $memory.skill_boundary.skill_memory_grants_tools $false
Assert-Equal 'Skill memory data-scope expansion' $memory.skill_boundary.skill_memory_expands_data_scope $false

$skill = Read-Policy 'enterprise-skill-lifecycle-policy.json'
foreach ($state in @('candidate', 'static_checked', 'isolated_trial', 'approved', 'active')) {
    Assert-Contains 'Skill lifecycle states' $skill.states $state
}
Assert-Equal 'Skill reuse authority' $skill.hard_boundaries.skill_reuse_grants_execution $false
Assert-Equal 'Skill tool authority' $skill.hard_boundaries.skill_install_grants_tools $false

$tool = Read-Policy 'enterprise-tool-governance-policy.json'
foreach ($layer in @('decision', 'lifecycle', 'verification', 'authorization', 'feedback_evolution')) {
    Assert-Contains 'Tool governance layers' $tool.layers $layer
}
Assert-Equal 'Tool authorization boundary' $tool.authorization_boundary 'tool_capability_never_grants_business_data_or_action_authority'
Assert-Equal 'Generated tool production boundary' $tool.hard_boundaries.generated_tool_direct_production $false
Assert-Equal 'Tool feedback permission boundary' $tool.hard_boundaries.feedback_changes_permission $false
Assert-Equal 'Tool feedback grant boundary' $tool.hard_boundaries.learning_expands_grant $false

$handbook = Read-Policy 'enterprise-governance-handbook-policy.json'
Assert-Contains 'Handbook progressive disclosure' $handbook.progressive_disclosure 'behavior'
Assert-Equal 'Handbook production mutation boundary' $handbook.resync_rules.auto_mutate_production_code $false
Assert-Equal 'Handbook approval mutation boundary' $handbook.resync_rules.auto_approve_policy_change $false
Assert-Equal 'Handbook stale-card action' $handbook.resync_rules.stale_card_action 'block_promotion_and_request_review'

$obsidian = Read-Policy 'obsidian-integration-policy.json'
Assert-Equal 'Obsidian source of truth' $obsidian.system_of_record.identity_permission_approval_budget_audit_evidence 'beijixing'
foreach ($noteClass in $obsidian.allowed_note_classes) {
    if ($noteClass -notin @('public', 'internal_sanitized')) { $failures.Add("Obsidian outbox cannot allow '$noteClass'.") }
}
Assert-Equal 'Obsidian permission boundary' $obsidian.hard_boundaries.vault_text_grants_permission $false
Assert-Equal 'Obsidian approval boundary' $obsidian.hard_boundaries.vault_text_changes_approval $false
Assert-Equal 'Obsidian budget boundary' $obsidian.hard_boundaries.vault_text_changes_budget $false
Assert-Equal 'Obsidian data-scope boundary' $obsidian.hard_boundaries.vault_text_changes_data_scope $false
Assert-Equal 'Obsidian Sync default' $obsidian.hard_boundaries.direct_obsidian_sync_enabled_by_default $false

$memoryContractPath = Join-Path $projectRoot '.qianlima\specifications\enterprise-memory-record-contract.json'
$contract = Get-Content -LiteralPath $memoryContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal 'Memory contract read Grant boundary' $contract.rules.read_requires_task_grant_and_scope_match $true
Assert-Equal 'Memory contract share boundary' $contract.rules.cross_agent_read_requires_revocable_share_grant $true
Assert-Equal 'Memory contract cross-organization boundary' $contract.rules.cross_organization_share_is_denied $true
Assert-Contains 'Memory prohibited content' $contract.prohibited_content 'secret_value'
Assert-Contains 'Memory prohibited content' $contract.prohibited_content 'raw_customer_data'

if ($failures.Count -gt 0) {
    throw ("Enterprise governance extension regression failed:`n - " + ($failures -join "`n - "))
}

$result = [pscustomobject]@{ passed = $true; checks = 31; enterprise_root = $enterpriseRoot }
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
