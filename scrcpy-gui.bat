@echo off
rem Launch scrcpy settings GUI.
rem Do not use pwsh WindowStyle Hidden here because it hides the GUI window too.
if not defined WINDIR set "WINDIR=%SystemDrive%\Windows"
start "" pwsh -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scrcpy-gui.ps1"
