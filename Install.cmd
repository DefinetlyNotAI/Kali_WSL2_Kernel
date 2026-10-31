@echo off
where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7 is required. Install it with winget install Microsoft.PowerShell
    pause
    exit /b 1
)
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
pause
