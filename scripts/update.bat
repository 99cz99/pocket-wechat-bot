@echo off
cd /d "%~dp0.."
echo Starting update...
powershell -ExecutionPolicy Bypass -File "%~dp0update.ps1" 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Update failed with code %ERRORLEVEL%
    echo If you see garbled text above, re-run deploy.bat instead.
)
pause
