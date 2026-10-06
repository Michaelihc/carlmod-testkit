@echo off
rem Check prerequisites.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\_run.ps1" Test-Prerequisites.ps1 %*
echo.
pause
