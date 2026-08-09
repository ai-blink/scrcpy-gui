@echo off
rem Compatibility launcher for the compiled WPF application.
setlocal
set "APP_EXE=%~dp0app\ScrcpyGui.exe"

if not exist "%APP_EXE%" (
  echo Building the WPF application for the first run...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish-wpf.ps1"
  if errorlevel 1 (
    echo.
    echo The WPF application could not be built. Install the .NET 8 SDK and try again.
    pause
    exit /b 1
  )
)

start "" /D "%~dp0" "%APP_EXE%"
exit /b 0
