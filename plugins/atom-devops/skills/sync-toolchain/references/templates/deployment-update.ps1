<#
.SYNOPSIS
    Updates the deployed {{SolutionName}} stack to the current images.

.DESCRIPTION
    Wraps the four steps an update needs, in the order they have to happen:

      1. Pull the images from the host. The app host cannot do this itself: DCP runs the docker CLI
         inside a container, and registry credentials are client-side (~/.docker/config.json, often
         behind a credential helper), so a pull from in there is anonymous and a private registry
         answers "error from registry: unauthorized".

      2. Stop the app host. It has to be down for step 3: DCP does not reconcile a container that
         disappears underneath it, so removing them while it runs simply leaves the app off until the
         app host is restarted anyway.

      3. Remove the api and web containers. They are ContainerLifetime.Persistent, which means DCP
         adopts them as they are on start-up and never re-examines the image. Skipping this leaves the
         previous build running while the dashboard reports everything healthy — the update silently
         does nothing. Removing them is the only thing that forces a recreate.

      4. Start the app host, which recreates both containers from the images pulled in step 1.

.PARAMETER EnvFile
    Env file passed to docker compose. Defaults to .env next to this script.

.PARAMETER SkipPull
    Skip the pull and recreate the containers from the images already on this machine. This is what you
    want after building images locally, where pulling would replace your build with the published one.

.EXAMPLE
    .\update.ps1

.EXAMPLE
    .\update.ps1 -SkipPull
#>
[CmdletBinding()]
param(
    [string]$EnvFile = ".env",
    [switch]$SkipPull
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan

    & $Action

    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    if ($exitCode -ne 0) {
        Write-Error "Step failed: $Name (exit code $exitCode)."
        exit $exitCode
    }

    Write-Host "OK: $Name" -ForegroundColor Green
}

Push-Location $PSScriptRoot
try {
    if (-not (Test-Path $EnvFile)) {
        Write-Error "Env file '$EnvFile' not found. Copy .env.example to .env and fill it in."
        exit 1
    }

    if ($SkipPull) {
        Write-Host "Skipping the pull; using the images already on this machine." -ForegroundColor Yellow
    }
    else {
        Invoke-Step "Pull images" {
            # --profile pull reaches the api and web services, which exist in the compose file only so
            # that they can be pulled from here; `up` never starts them.
            docker compose --env-file $EnvFile --profile pull pull
        }
    }

    Invoke-Step "Stop the app host" {
        # Must precede the removal: DCP only builds its resource model at start-up, so a container
        # removed while it is running is not noticed and simply stays gone.
        docker compose --env-file $EnvFile down
    }

    Invoke-Step "Remove the managed containers so DCP recreates them" {
        foreach ($containerName in @("{{ServicePrefix}}-api", "{{ServicePrefix}}-web")) {
            # Existence is checked first rather than letting `docker rm` fail on a container that is not
            # there. Its "No such container" goes to stderr, and Windows PowerShell 5.1 turns native
            # stderr piped through 2>&1 into a TERMINATING error under $ErrorActionPreference = "Stop" —
            # so on a first run the script died here, before it could start anything. PowerShell 7 does
            # not do that, which is why it only breaks for some people. Never redirect native stderr
            # into the pipeline in this script.
            $existing = docker ps --all --quiet --filter "name=^$containerName$"
            if (-not $existing) {
                Write-Host "   $containerName is not present - nothing to remove" -ForegroundColor DarkGray
                continue
            }

            docker rm --force $containerName | Out-Null
            Write-Host "   removed $containerName"
        }
    }

    Invoke-Step "Start the app host" {
        docker compose --env-file $EnvFile up -d
    }

    Write-Host ""
    Write-Host "Updated. The app host recreates the api and web containers; give it a few seconds." -ForegroundColor Green
    Write-Host "  Dashboard: http://localhost:{{DashboardPort}}"
    Write-Host "  SPA:       http://localhost:{{WebHostPort}}"
    Write-Host "  API:       http://localhost:{{ApiHostPort}}"
}
finally {
    Pop-Location
}
