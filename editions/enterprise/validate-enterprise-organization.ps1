<##
.SYNOPSIS
  Validates the active Enterprise organization and unique platform administrator.
.DESCRIPTION
  Read-only fail-closed validation. The platform administrator is the active
  member whose role template has platform_admin=true; role names are not trusted
  as authority without the role template.
##>
param(
  [string]$OrganizationPath='',
  [switch]$PassThru
)

$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$enterpriseRoot=$PSScriptRoot
$rolesPath=Join-Path $enterpriseRoot 'organization-role-templates.json'
if([string]::IsNullOrWhiteSpace($OrganizationPath)){$OrganizationPath=Join-Path $projectRoot '.qianlima\local-data\enterprise\organization.json'}
function Emit([object]$Value,[int]$Code=0){if($PassThru){$Value|ConvertTo-Json -Depth 12}else{$Value|Format-List};if($Code-ne 0){exit $Code}}
if(-not(Test-Path -LiteralPath $OrganizationPath -PathType Leaf)){Emit ([ordered]@{status='blocked';reason='organization_profile_missing';execution_authorized=$false;external_calls=$false}) 1}
try{$organization=Get-Content -LiteralPath $OrganizationPath -Raw -Encoding UTF8|ConvertFrom-Json;$roles=Get-Content -LiteralPath $rolesPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{Emit ([ordered]@{status='blocked';reason='organization_profile_invalid';execution_authorized=$false;external_calls=$false}) 1}
$issues=[System.Collections.Generic.List[string]]::new()
if([string]::IsNullOrWhiteSpace([string]$organization.organization_id)){[void]$issues.Add('organization_id_required')}
$members=@($organization.members|Where-Object{$_.enabled-eq$true})
if($members.Count-eq 0){[void]$issues.Add('active_member_required')}
$duplicateIds=@($members|Group-Object employee_id|Where-Object{$_.Name-and$_.Count-gt 1});if($duplicateIds.Count){[void]$issues.Add('active_employee_ids_must_be_unique')}
$owner=@($members|Where-Object{$_.role-eq'business_owner'});if($owner.Count-ne 1){[void]$issues.Add('exactly_one_active_business_owner_required')}
$platformRoles=@($roles.roles|Where-Object{$_.platform_admin-eq$true}|ForEach-Object{$_.id})
$admins=@($members|Where-Object{$_.role-in$platformRoles});if($admins.Count-ne 1){[void]$issues.Add('exactly_one_active_platform_admin_required')}
if($owner.Count-eq 1-and$admins.Count-eq 1-and[string]$owner[0].employee_id-eq[string]$admins[0].employee_id){[void]$issues.Add('business_owner_and_platform_admin_must_be_distinct')}
if([string]$organization.setup_status-ne'ready_for_employee_import'){[void]$issues.Add('organization_setup_not_ready')}
$result=[ordered]@{status=if($issues.Count){'blocked'}else{'ready'};organization_id=[string]$organization.organization_id;business_owner_id=if($owner.Count-eq 1){[string]$owner[0].employee_id}else{$null};platform_admin_id=if($admins.Count-eq 1){[string]$admins[0].employee_id}else{$null};issues=@($issues);execution_authorized=$false;external_calls=$false;files_written=$false}
Emit $result $(if($issues.Count){1}else{0})
