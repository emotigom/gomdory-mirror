@echo off
setlocal
cd /d "%~dp0"

set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL_EXE%" (
  echo Windows PowerShell was not found.
  echo Gomdory Mirror requires Windows 10 or Windows 11.
  pause
  exit /b 1
)

set "LOG_DIR=%LOCALAPPDATA%\GomdoryMirror"
set "LOG_FILE=%LOG_DIR%\startup.log"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
echo [%date% %time%] Gomdory Mirror start>>"%LOG_FILE%"
start "Gomdory Mirror" "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0app\GomdoryMirror.ps1" 1>>"%LOG_FILE%" 2>&1
exit /b 0
