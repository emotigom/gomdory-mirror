@echo off
setlocal
cd /d "%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo Windows PowerShell을 찾을 수 없습니다.
  echo Windows 10 또는 Windows 11에서 실행해 주세요.
  pause
  exit /b 1
)

start "Gomdory Mirror" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0app\GomdoryMirror.ps1"
exit /b 0
