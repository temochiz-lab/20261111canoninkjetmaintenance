@echo off
setlocal
set "G6030_PRINT_SCRIPT=C:\ProgramData\G6030Maintenance\Print-G6030Maintenance.ps1"
if not exist "%G6030_PRINT_SCRIPT%" (
    echo Setup is required. Run the setup batch file first.
    pause
    exit /b 1
)
echo This will print one maintenance page now, regardless of the interval.
choice /C YN /N /M "Print one page? [Y/N]: "
if errorlevel 2 exit /b 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%G6030_PRINT_SCRIPT%" -Force
set "G6030_RESULT=%ERRORLEVEL%"
echo.
echo Finished. Exit code: %G6030_RESULT%
echo Log: C:\ProgramData\G6030Maintenance\logs\maintenance.log
pause
exit /b %G6030_RESULT%
