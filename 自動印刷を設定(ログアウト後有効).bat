@echo off
setlocal
set "G6030_SETUP_LAUNCHER=%~dp0Start-G6030Setup.ps1"
if not exist "%G6030_SETUP_LAUNCHER%" (
    echo Start-G6030Setup.ps1 was not found next to this batch file.
    pause
    exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%G6030_SETUP_LAUNCHER%" -RunWhenLoggedOut
if errorlevel 1 (
    echo Setup could not start or administrator approval was cancelled.
    pause
    exit /b 1
)
exit /b 0
