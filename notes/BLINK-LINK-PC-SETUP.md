# scrcpy-gui Blink Link 준비 기능

2026-11-11 · PC 로컬 빌드0.4.2 / 동봉 Android 앱0.3.2.

## 사용자 흐름

1. 기존 scrcpy-gui의 페어링/기기 찾기로 휴대폰을 연결한다.
2. 상단 **Blink Link 설정**을 누른다.
3. 목록에서 대상 휴대폰을 확인하고 **이 휴대폰에 설치 · 권한 설정**을 누른다.
4. PC 앱이 설치·권한 부여·적용 확인을 처리하고 휴대폰에서 Blink Link를 연다.
5. Android 시스템의 위치·알림 허용과 사용할 Wi-Fi 등록은 휴대폰 앱 안내에서 진행한다.

일반 사용자에게 주소나 ADB 명령 입력을 요구하지 않는다. HTML 설명서와 Android README도 이 흐름을 기본으로 바꿨다. 설치 버튼과 결과는 대화상자 하단에 고정하고 설명만 스크롤한다.

## 동작

- APK를 WPF 실행 파일에 EmbeddedResource로 포함한다. 매 작업에서 고유 임시 폴더에 추출하고 SHA-256을 확인한다.
- adb.exe와 기기 목록은 기존 PC 연결 기능을 사용한다. 오프라인/허용 대기 기기는 설치 대상에 넣지 않는다.
- 선택한 serial과 adb 실행 파일을 작업 시작 시 고정한다. 모든 변경/확인 명령은 명시적인 `-s serial`로 실행하며 다른 기기로 대체하지 않는다.
- `get-state`와 현재 Android user 확인 → `install --user N -r` → 연결/user 재확인 → Blink Link의 WRITE_SECURE_SETTINGS 부여 → 해당 패키지 dumpsys에서 실제 grant 확인 → 명시 user로 앱 열기.
- Android16 package shell에는 check-permission 명령이 없어, 패키지/사용자 범위를 확인한 permission dump를 사용한다. 전역 development grant와 사용자별 grant를 구분하며 다른 사용자의 runtime grant로 통과시키지 않는다.
- 설치는 업데이트 방식이며 기존 앱 삭제·데이터 초기화·강제 다운그레이드·ADB 서버 종료를 하지 않는다. 취소나 실패는 이미 적용된 설치·권한을 되돌리지 않는다.
- 설치 제한120초, 그 외 명령12~20초. 창을 닫으면 진행 중 클라이언트 명령을 취소한다. 공유 ADB 서버를 종료하지 않는다.
- publish-wpf.ps1은 APK가 없으면 기존 Android 빌드를 먼저 실행한다. 소스 빌드에는 해당 Android SDK/JDK가 필요하지만 배포 exe에는 APK와 .NET 런타임이 포함된다.

## 검사

- `dotnet run --project tests/BlinkLinkSetup.Tests -c Release`:23개 assertion 통과. 기기 고정, 사용자 변경, 설치/권한 실패 시 후속 작업 차단, 취소, 잘못된 APK 거절, 배포용 WPF DLL의 embedded APK 해시를 검사한다. GUI나 기기 입력을 사용하지 않는다.
- 전용 Android16 AVD BlinkLink16 / emulator-5580에서 최초 권한을 해제한 다음 같은 provisioning 클래스로 실제 install→grant→dumpsys verify→am start가 통과했다. 각 명령 전 AVD 이름과 qemu 속성을 확인했다. 결과: `work/pc-blink-setup/android-integration.txt`.
- WPF 배포 및 기존 RemoteControls.Tests 프로젝트 컴파일:경고0/오류0. 기존 전체 WPF GUI 검사 프로그램은 호스트에서 실행하지 않았다.
- 최초에는 Hyper-V 접근 권한이 부족했으나 사용자의 명시적 UAC 승인 후 다시 실행했다. VM ID·게스트 UUID·디스크 체인·네트워크 어댑터 없음 검증을 통과한 BCU-Comparison-Windows의 TestAgent 데스크톱에서만 WPF 검사를 실행했다.
- Windows UI8개 assertion 통과: 800/640 폭에서 버튼 표시, 주소 입력 없이 대상 선택, 설치 버튼 하단 고정, 진행 중 대상 변경 방지, 선택 기기 고정 명령, 완료 후 재활성화, 설치 클릭→완료. 이 GUI 검사는 가짜 ADB를 사용하며 실제 Android 설치 검사는 별도 AVD에서 수행했다. 결과와 렌더링 PNG: `work/pc-blink-setup/hyperv/`. 호스트 키보드·마우스 입력은 주입하지 않았다.
- APK0.3.2의 PC 설정 안내에서 수동 명령/복사 버튼을 제거하고 PC 상단 Blink Link 설정 버튼을 안내한다. Android16 AVD에 새 APK를 설치해 안내 문구와 명령 입력 UI 부재를 확인했다. PNG/XML: `work/android-lab/pc-guide-032/`.
- 설명서 목차, 링크 대상, APK 링크, GUI 기본 안내를 정적으로 확인했다.

## 산출물

- `app/ScrcpyGui.exe` (로컬0.4.2): `b8696efc4c15126f8bb7bb3f36b0548b4929b4da73f59805551c7ef863fbac99` (SHA-256).
- 동봉 APK0.3.2: `affd1245bc6e150ee0c1ffd2ea18e0eaa0231fac66483002819c0419841cce61`.
- HTML: `app/android/BlinkLink-guide.html`, 원본 `android/manual.html`.

사용자가 변경해 둔 MainWindow.xaml의 창 높이857 및 무관한 VMware 녹화 폴더를 보존했다. 새 버튼은 기존 WrapPanel에 코드로 추가한다.
