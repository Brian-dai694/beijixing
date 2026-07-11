param(
  [string]$Root = '',
  [string]$OutputPath = '',
  [switch]$Json
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

$eventPath = Join-Path (Join-Path $Root 'logs') 'experience-events.jsonl'
$events = @()
if (Test-Path -LiteralPath $eventPath -PathType Leaf) {
  $events = @(Get-Content -LiteralPath $eventPath -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Get-Average([object[]]$Values) {
  if ($Values.Count -eq 0) { return $null }
  return [math]::Round(($Values | Measure-Object -Average).Average, 2)
}
function Get-Rate([object[]]$Values) {
  if ($Values.Count -eq 0) { return $null }
  return [math]::Round((($Values | Where-Object { $_ }).Count / $Values.Count), 4)
}

$firstDeliveries = @($events | Where-Object { $_.event_type -eq 'first_delivery' })
$finalDeliveries = @($events | Where-Object { $_.event_type -eq 'final_delivery' })
$evidenceValues = @($finalDeliveries | Where-Object { $null -ne $_.evidence_complete } | ForEach-Object { [bool]$_.evidence_complete })
$adoptionValues = @($events | Where-Object { $null -ne $_.user_adopted } | ForEach-Object { [bool]$_.user_adopted })
$snapshotValues = @($events | Where-Object { $null -ne $_.snapshot_hit } | ForEach-Object { [bool]$_.snapshot_hit })
$latencyByComponent = @($events | Group-Object component | ForEach-Object {
  [PSCustomObject]@{
    component = $_.Name
    event_count = $_.Count
    average_latency_ms = Get-Average @($_.Group | ForEach-Object { [double]$_.latency_ms })
  }
})

$dashboard = [PSCustomObject]@{
  schema_version = 1
  generated_at = (Get-Date).ToString('o')
  event_count = $events.Count
  first_useful_output_ms_average = Get-Average @($firstDeliveries | ForEach-Object { [double]$_.latency_ms })
  final_delivery_ms_average = Get-Average @($finalDeliveries | ForEach-Object { [double]$_.latency_ms })
  evidence_completeness_rate = Get-Rate $evidenceValues
  user_adoption_rate = Get-Rate $adoptionValues
  snapshot_hit_rate = Get-Rate $snapshotValues
  latency_by_component = [object[]]$latencyByComponent
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $workingPath = Join-Path $Root 'working'
  if (-not (Test-Path -LiteralPath $workingPath -PathType Container)) {
    New-Item -ItemType Directory -Path $workingPath -Force | Out-Null
  }
  $OutputPath = Join-Path $workingPath 'quality-dashboard.json'
}

$serialized = $dashboard | ConvertTo-Json -Depth 6
$serialized | Set-Content -LiteralPath $OutputPath -Encoding UTF8
if ($Json) { $serialized } else { $dashboard | Format-List }
