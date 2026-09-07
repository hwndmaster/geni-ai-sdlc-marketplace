@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%publish-docker.ps1"

if not exist "%PS_SCRIPT%" (
    echo ERROR: Script not found: "%PS_SCRIPT%"
    exit /b 1
)

where pwsh >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "PS_EXE=pwsh"
) else (
    set "PS_EXE=powershell"
)

%PS_EXE% -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if NOT "%EXIT_CODE%"=="0" (
    echo.
    echo Publish failed with exit code %EXIT_CODE%.
    exit /b %EXIT_CODE%
)

echo.
echo Publish completed successfully.
exit /b 0
