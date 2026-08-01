@echo off
chcp 65001 >nul
setlocal

rem ============================================================
rem  scrcpy 무선 실행 (Galaxy S23 Ultra / Android 16)
rem  방식: Android 11+ 무선 디버깅 페어링 + mDNS 자동 탐색
rem  - adb tcpip 안 씀  -> USB 케이블 불필요
rem  - 폰 IP 하드코딩 안 씀 -> 공유기가 IP를 바꿔도 동작
rem  최초 1회 페어링은 이미 완료됨 (폰에 저장되어 재부팅해도 유지)
rem
rem  설정을 화면에서 바꾸려면 scrcpy-gui.bat 을 쓰세요.
rem ============================================================

set "SCRCPY=C:\app\scrcpy-win64-v4.1\scrcpy.exe"
if not exist "%SCRCPY%" (
  echo [실패] scrcpy.exe 를 찾을 수 없습니다: %SCRCPY%
  echo        이 파일 위쪽 SCRCPY 경로를 실제 설치 위치로 고치세요.
  pause
  exit /b 1
)

rem 이전 scrcpy 정리 (PID 하드코딩은 엉뚱한 프로세스를 죽일 수 있어 이미지명 사용)
taskkill /f /im scrcpy.exe >nul 2>&1

echo [1/2] 폰 탐색 중...
adb devices >nul
timeout /t 2 /nobreak >nul
adb devices

echo.
echo [2/2] scrcpy 실행...
"%SCRCPY%" --max-size 1850 --max-fps 120 -b 8M --screen-off-timeout=500 --keyboard=uhid

if errorlevel 1 (
  echo.
  echo ============================================================
  echo  [실패] 폰에 연결하지 못했습니다.
  echo.
  echo  폰에서 확인하세요:
  echo    설정 - 개발자 옵션 - 무선 디버깅  ON
  echo    ^(폰을 재부팅했다면 꺼져 있습니다. 퀵설정 타일로 1탭 복구^)
  echo.
  echo  그래도 안 되면 폰과 PC가 같은 Wi-Fi 인지 확인하세요.
  echo ============================================================
  pause
)

endlocal
