@echo off
rem scrcpy 설정 GUI 실행기
rem ※ pwsh 에 -WindowStyle Hidden 을 붙이면 GUI 창까지 숨겨진다(실측). 콘솔 숨김은 ps1 안에서 처리함.
start "" pwsh -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scrcpy-gui.ps1"
