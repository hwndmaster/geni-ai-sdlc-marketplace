<#
.SYNOPSIS
    Updates {{SolutionName}} under the app host. The first run installs it.

.DESCRIPTION
    Five steps, in the order they have to happen:

      1. Pull {{SolutionName}}'s images, on this server. The app host cannot do this itself: registry
         credentials are client-side, so a pull from inside its container is anonymous and a private
         registry answers "unauthorized".

      2. Stop the app host. The other applications keep running: their containers are persistent and do
         not depend on it.

      3. Remove {{ServicePrefix}}-api and {{ServicePrefix}}-web. On start-up the app host attaches to any
         container it finds without checking which image it runs, so removing them is the only way to get
         the new images in.

      4. Start the app host. It reads app.json and .env again and creates the two containers.

      5. Wait until both run.

    Every application's update.ps1, and the app host's own, take one machine-wide lock first, so two updates
    never stop the app host under each other.

.PARAMETER SkipPull
    Recreate the containers from the images already on this machine: after changing app.json or .env, or
    after a local build, where pulling would replace it with the published one.

.EXAMPLE
    .\update.ps1

.EXAMPLE
    .\update.ps1 -SkipPull
#>
[CmdletBinding()]
param(
    [switch]$SkipPull,
    [int]$TimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$LockName = "Global\AppHostUpdate"
$AppHost = "app-host"
$Containers = @("{{ServicePrefix}}-api", "{{ServicePrefix}}-web")

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

# Existence is checked rather than letting docker fail on a missing container. Its "No such container" goes
# to stderr, and Windows PowerShell 5.1 turns native stderr piped through 2>&1 into a TERMINATING error under
# $ErrorActionPreference = "Stop", while PowerShell 7 does not. Never redirect native stderr into the
# pipeline in this script.
function Test-Container {
    param([Parameter(Mandatory = $true)] [string]$Name)

    return [bool](docker ps --all --quiet --filter "name=^$Name$")
}

function Test-ContainerRunning {
    param([Parameter(Mandatory = $true)] [string]$Name)

    return (Test-Container $Name) -and ((docker inspect --format "{{.State.Running}}" $Name) -eq "true")
}

Push-Location $PSScriptRoot
$lock = [System.Threading.Mutex]::new($false, $LockName)
$lockTaken = $false
try {
    if (-not (Test-Path ".env")) {
        Write-Error ".env not found next to this script. Create it from the example and fill it in: Copy-Item .env.example .env"
        exit 1
    }

    if (-not (Test-Container $AppHost)) {
        Write-Error "No '$AppHost' container on this machine. Install the app host first: see its Deployment\README.md."
        exit 1
    }

    Write-Host "Waiting for any other app host or application update to finish..." -ForegroundColor DarkGray
    try {
        $lockTaken = $lock.WaitOne([TimeSpan]::FromMinutes(10))
    }
    catch [System.Threading.AbandonedMutexException] {
        # A previous update was killed while holding the lock. The lock is ours now.
        $lockTaken = $true
    }

    if (-not $lockTaken) {
        Write-Error "Another update has held the lock for 10 minutes. Check for a stuck update.ps1 window."
        exit 1
    }

    if ($SkipPull) {
        Write-Host "Skipping the pull; using the images already on this machine." -ForegroundColor Yellow
    }
    else {
        Invoke-Step "Pull {{SolutionName}}'s images" {
            docker compose --env-file .env --profile pull pull
        }
    }

    Invoke-Step "Stop the app host" {
        docker stop $AppHost | Out-Null
    }

    Invoke-Step "Remove {{SolutionName}}'s containers" {
        foreach ($name in $Containers) {
            if (Test-Container $name) {
                docker rm --force $name | Out-Null
                Write-Host "   removed $name"
            }
            else {
                Write-Host "   $name is not present - nothing to remove" -ForegroundColor DarkGray
            }
        }
    }

    Invoke-Step "Start the app host" {
        docker start $AppHost | Out-Null
    }

    Invoke-Step "Wait for {{SolutionName}} to run" {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (-not ((Test-ContainerRunning $Containers[0]) -and (Test-ContainerRunning $Containers[1]))) {
            if (-not (Test-ContainerRunning $AppHost)) {
                docker logs --tail 30 $AppHost
                Write-Error "The app host stopped. Its last log lines are above."
                exit 1
            }

            if ((Get-Date) -gt $deadline) {
                Write-Error ("{{SolutionName}} did not start within $TimeoutSeconds seconds. The dashboard's Resources page " +
                    "shows it with the reason, or does not show it at all when apps.json does not register it.")
                exit 1
            }

            Start-Sleep -Seconds 2
        }
    }

    Write-Host ""
    Write-Host "{{SolutionName}} is updated and running." -ForegroundColor Green
}
finally {
    if ($lockTaken) {
        $lock.ReleaseMutex()
    }

    $lock.Dispose()
    Pop-Location
}
