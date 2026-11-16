param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("up", "down", "status")]
    [string]$Action
)

$ErrorActionPreference = "Stop"

# Fixed targets: this script only ever touches these resources.
$ExpectedProject  = "itp-agentspace"
$Region           = "us-central1"
$DbInstance       = "trebol-poc-db-c124"
$Service          = "trebol-poc-app"
$UpMinInstances   = 2
$DownMinInstances = 0

function Invoke-Gcloud {
    $out = & gcloud.cmd @args
    if ($LASTEXITCODE -ne 0) {
        throw "gcloud failed: gcloud $($args -join ' ')"
    }
    return $out
}

# Safety check: refuse to run against any other project.
$project = (Invoke-Gcloud config get-value project | Select-Object -First 1).Trim()
if ($project -ne $ExpectedProject) {
    throw "Active gcloud project is '$project', expected '$ExpectedProject'. Aborting."
}

function Get-Service-Json {
    $json = (Invoke-Gcloud run services describe $Service --region $Region --format=json) -join "`n"
    return $json | ConvertFrom-Json
}

function Show-Status {
    $db = Invoke-Gcloud sql instances describe $DbInstance --format="value(state,settings.activationPolicy)"
    Write-Host "Cloud SQL ($DbInstance): $db   [state, activation policy]"
    $svc = Get-Service-Json
    $min = $svc.spec.template.metadata.annotations.'autoscaling.knative.dev/minScale'
    if (-not $min) { $min = "not set (0)" }
    Write-Host "Cloud Run ($Service): min instances = $min"
    Write-Host "URL: $($svc.status.url)"
}

function Set-CloudRunMin([int]$count) {
    Invoke-Gcloud run services update $Service --region $Region --min-instances $count --quiet | Out-Null
}

function Wait-DbOperations([int]$TimeoutMinutes = 20) {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ($true) {
        $pending = Invoke-Gcloud sql operations list --instance=$DbInstance --filter="status!=DONE" --format="value(name)"
        if (-not $pending) { return }
        if ((Get-Date) -gt $deadline) {
            throw "A Cloud SQL operation is still running after $TimeoutMinutes minutes."
        }
        Write-Host "  ...Cloud SQL operation in progress, waiting (it continues on Google's side if you stop this)"
        Start-Sleep -Seconds 15
    }
}

function Set-DbPolicy([string]$policy) {
    Wait-DbOperations
    Invoke-Gcloud sql instances patch $DbInstance --activation-policy=$policy --async --quiet | Out-Null
    Wait-DbOperations
    $actual = (Invoke-Gcloud sql instances describe $DbInstance --format="value(settings.activationPolicy)" | Select-Object -First 1).Trim()
    if ($actual -ne $policy) {
        throw "Expected activation policy $policy but found $actual"
    }
}

function Test-Health {
    $url   = (Get-Service-Json).status.url
    $token = (Invoke-Gcloud auth print-identity-token | Select-Object -First 1).Trim()
    try {
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 `
            -Uri "$url/actuator/health/readiness" `
            -Headers @{ "X-Serverless-Authorization" = "Bearer $token" }
        Write-Host "Health check: HTTP $($r.StatusCode) $($r.Content)"
    }
    catch {
        Write-Host "Health check FAILED: $($_.Exception.Message)"
    }
}

switch ($Action) {
    "status" {
        Show-Status
    }
    "up" {
        Write-Host "Starting Cloud SQL (takes 1-3 minutes)..."
        Set-DbPolicy "ALWAYS"
        Write-Host "Setting Cloud Run minimum instances to $UpMinInstances..."
        Set-CloudRunMin $UpMinInstances
        Show-Status
        Test-Health
    }
    "down" {
        Write-Host "Setting Cloud Run minimum instances to $DownMinInstances..."
        Set-CloudRunMin $DownMinInstances
        Write-Host "Stopping Cloud SQL..."
        Set-DbPolicy "NEVER"
        Show-Status
    }
}