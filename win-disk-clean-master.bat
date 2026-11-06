@echo off
setlocal
chcp 65001 >nul
rem Starts Windows PowerShell 5.1 in the same user context. No auto elevation.
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0win-disk-clean-master.ps1"
if errorlevel 1 echo [ERROR] PowerShell script failed. Review output above.
pause
