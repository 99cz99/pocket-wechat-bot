@echo off
REM deploy.bat - Launcher for deploy.ps1 (UTF-8 Chinese)
powershell -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"
pause
