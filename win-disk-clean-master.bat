@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0win-disk-clean-master.ps1"
if errorlevel 1 echo [ERROR] PowerShell reported an error; review messages above.
pause
