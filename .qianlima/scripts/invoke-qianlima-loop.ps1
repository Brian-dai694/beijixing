param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')]
  [string]$WorkflowId,

  [ValidateSet('EVR')]
  [string]$LoopType = 'EVR',
  [ValidateSet('Start', 'Advance', 'Status')]
  [string]$Action = 'Status',
  [ValidateSet('execute_complete', 'verify_pass', 'verify_issues', 'verify_critical', 'refine_complete', 'stop')]
  [string]$Outcome = '',
  [string]$RunId = '',
  [ValidateRange(1, 10)]
  [int]$MaxIterations = 3,
  [string]$StatePath = '',
  [string]$Note = '',
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$traceDirectory = Join-Path $projectRoot '.qianlima\run-traces'

if ([string]::IsNullOrWhiteSpace($RunId)) {
  $RunId = "$WorkflowId-$((Get-Date).ToString('yyyyMMdd-HHmmss-fff'))"
}
if ([string]::IsNullOrWhiteSpace($StatePath)) {
  $StatePath = Join-Path $traceDirectory "loop-$RunId.json"
}

function Save-State([object]$State) {
  $directory = Split-Path -Parent $StatePath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }
  [System.IO.File]::WriteAllText($StatePath, ($State | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
}

function Add-History([object]$State, [string]$Event) {
  $State.history += [PSCustomObject]@{
    at = (Get-Date).ToUniversalTime().ToString('o')
    state = $State.current_state
    event = $Event
    note = $Note
  }
  $State.updated_at = (Get-Date).ToUniversalTime().ToString('o')
}

if ($Action -eq 'Start') {
  if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    throw "Loop state already exists: $StatePath"
  }
  $state = [PSCustomObject]@{
    schema_version = 1
    run_id = $RunId
    workflow_id = $WorkflowId
    loop_type = $LoopType
    current_state = 'execute'
    status = 'running'
    iteration = 0
    max_iterations = $MaxIterations
    started_at = (Get-Date).ToUniversalTime().ToString('o')
    updated_at = (Get-Date).ToUniversalTime().ToString('o')
    history = @()
  }
  Add-History $state 'started'
  Save-State $state
} else {
  if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
    throw "Loop state not found: $StatePath"
  }
  $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ($Action -eq 'Advance') {
  if ([string]::IsNullOrWhiteSpace($Outcome)) {
    throw 'Advance requires an Outcome.'
  }
  if ($state.status -ne 'running') {
    throw "Loop is already terminal: $($state.status)"
  }

  switch ($state.current_state) {
    'execute' {
      if ($Outcome -eq 'execute_complete') { $state.current_state = 'verify' }
      elseif ($Outcome -eq 'stop') { $state.current_state = 'stopped'; $state.status = 'stopped' }
      else { throw "Outcome $Outcome is invalid from execute." }
    }
    'verify' {
      if ($Outcome -eq 'verify_pass') { $state.current_state = 'completed'; $state.status = 'completed' }
      elseif ($Outcome -eq 'verify_critical') { $state.current_state = 'failed'; $state.status = 'failed' }
      elseif ($Outcome -eq 'verify_issues') {
        if ([int]$state.iteration -ge [int]$state.max_iterations) {
          $state.current_state = 'frozen'; $state.status = 'frozen'
        } else {
          $state.iteration = [int]$state.iteration + 1
          $state.current_state = 'refine'
        }
      } elseif ($Outcome -eq 'stop') { $state.current_state = 'stopped'; $state.status = 'stopped' }
      else { throw "Outcome $Outcome is invalid from verify." }
    }
    'refine' {
      if ($Outcome -eq 'refine_complete') { $state.current_state = 'verify' }
      elseif ($Outcome -eq 'stop') { $state.current_state = 'stopped'; $state.status = 'stopped' }
      else { throw "Outcome $Outcome is invalid from refine." }
    }
    default { throw "State $($state.current_state) cannot advance." }
  }
  Add-History $state $Outcome
  Save-State $state
}

if ($PassThru) {
  [PSCustomObject]@{ StatePath = $StatePath; State = $state }
} else {
  Write-Host "Loop state: $($state.current_state) / $($state.status)"
  Write-Host "Trace: $StatePath"
}
