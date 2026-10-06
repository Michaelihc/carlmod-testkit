@echo off
rem Start server, emulator and client, then connect.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\_run.ps1" Start-All.ps1 %*
echo.
pause
