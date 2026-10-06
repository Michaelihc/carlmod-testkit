@echo off
rem One-time setup: import the server, install the Android SDK, create the emulator.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\_run.ps1" Setup.ps1 %*
echo.
pause
