@echo off
rem Take an emulator screenshot and open it.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\_run.ps1" Capture.ps1 -Open %*
echo.
pause
