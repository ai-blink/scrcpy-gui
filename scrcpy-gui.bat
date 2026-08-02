@echo off
rem Launch scrcpy settings GUI.
rem Do not use pwsh WindowStyle Hidden here because it hides the GUI window too.
if not defined WINDIR set "WINDIR=%SystemDrive%\Windows"

rem Explorer can retain an old PATH after PowerShell 7 is installed. Check its
rem standard install locations first, then use PATH only as a final fallback.
set "PWSH_EXE="
for %%I in (
  "%ProgramFiles%\PowerShell\7\pwsh.exe"
  "%ProgramW6432%\PowerShell\7\pwsh.exe"
  "%LocalAppData%\Programs\PowerShell\7\pwsh.exe"
) do (
  if not defined PWSH_EXE if exist "%%~I" set "PWSH_EXE=%%~I"
)
if not defined PWSH_EXE for %%I in (pwsh.exe) do set "PWSH_EXE=%%~$PATH:I"

if not defined PWSH_EXE goto :missing_pwsh
if not exist "%PWSH_EXE%" goto :missing_pwsh

start "" "%PWSH_EXE%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scrcpy-gui.ps1"
exit /b 0

:missing_pwsh
rem The GUI requires PowerShell 7; Windows PowerShell is used only to show this
rem actionable error message because it is included with Windows 11.
"%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -Command "Add-Type -AssemblyName PresentationFramework; [void][System.Windows.MessageBox]::Show('PowerShell 7 or later (pwsh) is required but was not found.`n`nInstall PowerShell 7, then run this file again:`nhttps://github.com/PowerShell/PowerShell/releases', 'Cannot start scrcpy settings', 'OK', 'Error')"
exit /b 1
