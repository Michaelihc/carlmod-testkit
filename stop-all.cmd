@echo off
rem Stop the emulators and servers started by this kit.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\_run.ps1" Stop-All.ps1 %*
echo.
pause
