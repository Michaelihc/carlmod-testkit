@echo off
rem Send server console commands. Without arguments: interactive mode.
setlocal
set "TK_ARGS=%*"
if "%~1"=="" set "TK_ARGS=-Interactive"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\_run.ps1" Send-ServerCommand.ps1 %TK_ARGS%
echo.
pause
