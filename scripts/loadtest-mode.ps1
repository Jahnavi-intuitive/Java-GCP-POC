<#
.SYNOPSIS
  Temporarily scales Cloud Run for a load test, then puts it back.

.DESCRIPTION
  boost    Saves the CURRENT Cloud Run settings to loadtest-baseline.json, then applies
           load-test settings (more warm instances, concurrency 10 (earlier scale-out),
           2 vCPU, CPU always allocated).
  restore  Re-applies the saved baseline (falls back to the documented defaults).
  run      boost -> waits -Minutes -> restore. Restore also runs if you press Ctrl+C
           or the script fails, so the expensive settings cannot be left on by accident.
  status   Shows the live settings. Read-only.

  Only Cloud Run is touched. Cloud SQL is NOT started or stopped here: use
  scripts/poc.ps1 up / down for that (the DB must be up during the test).

  Cost note: boosted instances bill CPU+memory continuously while they exist.
  Keep the window short. Restore is the only thing that brings the bill back down.

.EXAMPLE
  .\scripts\loadtest-mode.ps1 run -Minutes 15
  .\scripts\loadtest-mode.ps1 boost -MinInstances 30 -MaxInstances 60
  .\scripts\loadtest-mode.ps1 restore
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("boost", "restore", "run", "status")]
    [string]$Action,

    [int]$MinInstances = 8,
    [int]$MaxInstances = 20,
    [int]$Concurrency  = 10,
    [string]$Cpu       = "2",
    [string]$Memory    = "2Gi",
    [ValidateRange(1, 120)]
    [int]$Minutes      = 15
)

$ErrorActionPreference = "Stop"

# Fixed targets: this script only ever touches this service.
$ExpectedProject = "itp-agentspace"
$Region          = "us-central1"
$Service         = "trebol-poc-app"
$StateFile       = Join-Path $PSScriptRoot "loadtest-baseline.json"

# Documented normal values (infra/terraform/cloudrun.tf), used if no baseline was saved.
$Defaults = @{ min = 0; max = 10; concurrency = 80; cpu = "1"; memory = "1Gi"; throttling = $true }

function Invoke-Gcloud {
    $out = & gcloud.cmd @args
    if ($LASTEXITCODE -ne 0) { throw "gcloud failed: gcloud $($args -join ' ')" }
    return $out
}

$project = (Invoke-Gcloud config get-value project | Select-Object -First 1).Trim()
if ($project -ne $ExpectedProject) {
    throw "Active gcloud project is '$project', expected '$ExpectedProject'. Aborting."
}

function Get-Settings {
    $svc  = ((Invoke-Gcloud run services describe $Service --region $Region --format=json) -join "`n") | ConvertFrom-Json
    $ann  = $svc.spec.template.metadata.annotations
    $c    = $svc.spec.template.spec.containers[0]
    $min  = $ann.'autoscaling.knative.dev/minScale'
    $max  = $ann.'autoscaling.knative.dev/maxScale'
    $thr  = $ann.'run.googleapis.com/cpu-throttling'
    return @{
        min         = if ($min) { [int]$min } else { 0 }
        max         = if ($max) { [int]$max } else { $Defaults.max }
        concurrency = [int]$svc.spec.template.spec.containerConcurrency
        cpu         = [string]$c.resources.limits.cpu
        memory      = [string]$c.resources.limits.memory
        throttling  = ($thr -ne "false")
    }
}

function Show-Status {
    $s = Get-Settings
    Write-Host ("Cloud Run {0}: min={1} max={2} concurrency={3} cpu={4} memory={5} cpu-throttling={6}" -f `
        $Service, $s.min, $s.max, $s.concurrency, $s.cpu, $s.memory, $s.throttling)
    if (Test-Path $StateFile) { Write-Host "Saved baseline: $StateFile" } else { Write-Host "No saved baseline (normal mode)." }
}

function Apply-Settings($s) {
    # Order matters: when going down, drop min before max; when going up, raise max before min.
    $thr = if ($s.throttling) { "--cpu-throttling" } else { "--no-cpu-throttling" }
    Invoke-Gcloud run services update $Service --region $Region `
        --max-instances $s.max --min-instances $s.min `
        --concurrency $s.concurrency --cpu $s.cpu --memory $s.memory `
        $thr --quiet | Out-Null
}

function Do-Boost {
    if (Test-Path $StateFile) {
        Write-Host "A baseline is already saved (a boost is probably active). Keeping it; re-applying load settings."
    } else {
        Get-Settings | ConvertTo-Json | Set-Content -Encoding utf8 $StateFile
        Write-Host "Baseline saved to $StateFile"
    }
    $boost = @{ min = $MinInstances; max = $MaxInstances; concurrency = $Concurrency; cpu = $Cpu; memory = $Memory; throttling = $false }
    Write-Host "BOOST: min=$MinInstances max=$MaxInstances concurrency=$Concurrency cpu=$Cpu memory=$Memory (CPU always on). Costs money until you run restore."
    Apply-Settings $boost
    Show-Status
}

function Do-Restore {
    if (Test-Path $StateFile) {
        $j = Get-Content $StateFile -Raw | ConvertFrom-Json
        $s = @{ min = [int]$j.min; max = [int]$j.max; concurrency = [int]$j.concurrency; cpu = [string]$j.cpu; memory = [string]$j.memory; throttling = [bool]$j.throttling }
        Write-Host "RESTORE from saved baseline."
    } else {
        $s = $Defaults
        Write-Host "No saved baseline; restoring documented defaults."
    }
    Apply-Settings $s
    if (Test-Path $StateFile) { Remove-Item $StateFile }
    Show-Status
}

switch ($Action) {
    "status"  { Show-Status }
    "boost"   { Do-Boost }
    "restore" { Do-Restore }
    "run" {
        try {
            Do-Boost
            Write-Host "Boosted for $Minutes minute(s). Run your k6 test now. Press Ctrl+C to restore early."
            $deadline = (Get-Date).AddMinutes($Minutes)
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 10
            }
        }
        finally {
            Write-Host "Restoring normal settings..."
            Do-Restore
        }
    }
}
