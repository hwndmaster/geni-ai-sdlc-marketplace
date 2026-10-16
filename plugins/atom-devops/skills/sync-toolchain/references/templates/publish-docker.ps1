[CmdletBinding()]
param(
    [Alias("GithubToken")]
    [string]$RegistryToken = $env:GITHUB_REGISTRY_TOKEN,
    [string]$AtomPkgAccessToken = $env:ATOM_PKG_ACCESS_TOKEN,
    [string]$DockerUser = "hwndmaster",
    [string]$Registry = "ghcr.io",
    [int]$DockerReadyTimeoutSeconds = 60,
    [switch]$NoAutoStartDockerDesktop
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan

    try {
        & $Action
    }
    catch {
        Write-Error "Step failed: $Name. $($_.Exception.Message)"
        exit 1
    }

    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    if ($exitCode -ne 0) {
        Write-Error "Step failed: $Name (exit code $exitCode)."
        exit $exitCode
    }

    Write-Host "OK: $Name" -ForegroundColor Green
}

function Test-DockerDaemonReady {
    & docker info *> $null
    return $LASTEXITCODE -eq 0
}

function Ensure-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error "Docker CLI was not found in PATH. Install Docker Desktop and try again."
        exit 1
    }

    & docker compose version *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker Compose v2 is required. Install/enable Docker Compose and try again."
        exit 1
    }

    if (Test-DockerDaemonReady) {
        return
    }

    $dockerDesktopExe = $null
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $dockerDesktopExe = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    }

    if (
        -not $NoAutoStartDockerDesktop -and
        -not [string]::IsNullOrWhiteSpace($dockerDesktopExe) -and
        (Test-Path $dockerDesktopExe)
    ) {
        Write-Host ""
        Write-Host "Docker daemon is not reachable. Starting Docker Desktop..." -ForegroundColor Yellow
        Start-Process -FilePath $dockerDesktopExe | Out-Null
    }

    $startTime = Get-Date
    while (((Get-Date) - $startTime).TotalSeconds -lt $DockerReadyTimeoutSeconds) {
        if (Test-DockerDaemonReady) {
            Write-Host "Docker daemon is ready." -ForegroundColor Green
            return
        }

        Start-Sleep -Seconds 2
    }

    Write-Error "Docker daemon is not reachable. Start Docker Desktop, ensure Linux containers are enabled, and retry."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($RegistryToken)) {
    Write-Error "Registry token is required. Provide -RegistryToken (or -GithubToken) or set GITHUB_REGISTRY_TOKEN."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($AtomPkgAccessToken)) {
    Write-Error "Package token is required. Provide -AtomPkgAccessToken or set ATOM_PKG_ACCESS_TOKEN."
    exit 1
}

Ensure-DockerReady

$apiImage = "$Registry/$DockerUser/{{ServicePrefix}}-api:latest"
$webImage = "$Registry/$DockerUser/{{ServicePrefix}}-web:latest"
$previousAtomPkgAccessToken = $env:ATOM_PKG_ACCESS_TOKEN
$hadPreviousAtomPkgAccessToken = $null -ne $previousAtomPkgAccessToken
$previousComposeParallelLimit = $env:COMPOSE_PARALLEL_LIMIT
$hadPreviousComposeParallelLimit = $null -ne $previousComposeParallelLimit
$env:ATOM_PKG_ACCESS_TOKEN = $AtomPkgAccessToken
$env:COMPOSE_PARALLEL_LIMIT = "1"

Push-Location $PSScriptRoot
try {
    Invoke-Step "Docker login to $Registry" {
        $RegistryToken | docker login $Registry -u $DockerUser --password-stdin
    }

    Invoke-Step "Build Docker compose images" {
        docker compose --progress=plain build {{ServicePrefix}}-api
        docker compose --progress=plain build {{ServicePrefix}}-web
    }

    Invoke-Step "Tag API image" {
        docker tag {{ComposeProject}}-{{ServicePrefix}}-api $apiImage
    }

    Invoke-Step "Tag Web image" {
        docker tag {{ComposeProject}}-{{ServicePrefix}}-web $webImage
    }

    Invoke-Step "Push API image" {
        docker push $apiImage
    }

    Invoke-Step "Push Web image" {
        docker push $webImage
    }

    Write-Host ""
    Write-Host "All steps completed successfully." -ForegroundColor Green
}
finally {
    if ($hadPreviousAtomPkgAccessToken) {
        $env:ATOM_PKG_ACCESS_TOKEN = $previousAtomPkgAccessToken
    }
    else {
        Remove-Item Env:\ATOM_PKG_ACCESS_TOKEN -ErrorAction SilentlyContinue
    }

    if ($hadPreviousComposeParallelLimit) {
        $env:COMPOSE_PARALLEL_LIMIT = $previousComposeParallelLimit
    }
    else {
        Remove-Item Env:\COMPOSE_PARALLEL_LIMIT -ErrorAction SilentlyContinue
    }

    Pop-Location
}
