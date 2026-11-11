# Blink Link 분석 및 검증 — 2026-11-11

이 문서는 **0.1.0 최초 구현의 역사적 기록**이다. 이후 리뷰에서 발견한 서비스 상태·재시도·테스트 판정 문제와 0.1.1 결과는 [리뷰 수정 기록](REVIEW-FIX-2026-11-11.md)에 구분해 기록한다. 아래 APK 해시는 0.1.0의 해시다.

## 범위와 결과

사용자는 MacroDroid를 확인했고, S23 Ultra / One UI 8.5 / Android 16을 대상 기기로 지정했다. `C:\ai\projects\ik`에서 사용 맥락을 파악하도록 허용했다. 구현은 등록 Wi-Fi에서 무선 디버깅을 복구하는 Android 앱이다. 다른 자주 쓰는 매크로 목록은 자료에서 발견하지 못했다.

APK 빌드·서명, 순수 정책 검사 10건, Android 16 가상 기기의 실행 검사 9건이 통과했다. 최초 권한이 없는 상태의 시작 차단과 Android 네트워크 허용 창도 별도로 직접 확인했다. S23 Ultra의 삼성 정책과 실제 PC 무선 미러링은 미확인이다. 화면의 켜짐은 `Settings.Global.adb_wifi_enabled` 값이며, 네트워크 연결 성공의 증거가 아니다. 에뮬레이터 `service.adb.tls.port` 값도 비어 있어 실제 TLS 연결 성립은 검증했다고 주장하지 않는다.

## 실제 읽은 자료

| 원본 | 읽은 범위와 사용 |
|---|---|
| `C:\ai\projects\ik\CLAUDE.md` | 자료 탐색·원본 보존·개인 경험과 추론 구분 |
| `C:\ai\projects\ik\전문분야\README.md` | 접근성 관련 자료 진입점 |
| `C:\ai\projects\ik\인물\장애와생활.md` | 안구마우스를 중요한 입력 수단으로 사용하는 생활 맥락 |
| `C:\ai\projects\ik\자료\추출문\S00504.md` | P0038·P0040 주변. 원고의 장면과 현재 기기 설정을 구분 |
| `C:\ai\projects\scrcpy-gui\README.md` | 무선 페어링과 PC 기기 찾기 기능 |
| `C:\Users\ikseon\Documents\Codex\2026-11-07\new-chat\outputs\2026-11-07-virtual-environment-decisions.md` | 격리·호스트 입력 금지 원칙 |
| `C:\ai\projects\background-lab\README.md` | 기존 실행기의 지원 범위 |
| [MacroDroid 공식 사이트](https://macrodroid.com/) | 트리거·동작·조건 기반 제품 구조 |
| [공식 포럼 6.2 배포 글](https://macrodroidforum.com/index.php?threads/v6-2.12550/) | 공식 universal 베타 APK 링크 확인. 사용자 휴대폰 설치 버전과 같다는 뜻은 아님 |
| [System Setting 문서](https://macrodroidforum.com/wiki/index.php/Action:_System_Setting) | 시스템 설정 변경과 특별 권한 경로. 웹 도구는 403, 로컬 HTTPS 요청으로 본문 취득 |
| [Helper App 문서](https://macrodroidforum.com/wiki/index.php/Helper_App) | 공식 보조 APK 링크 확인 |
| [Android 16 AdbService](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/services/core/java/com/android/server/adb/AdbService.java) | ADB_WIFI_ENABLED 설정 감시와 서비스 연결. `?format=TEXT` 원문을 디코딩해 읽음 |
| [Android 권한 문서](https://developer.android.com/reference/android/Manifest.permission#WRITE_SECURE_SETTINGS) | 특별 설정 권한의 성격 |
| [Android 에뮬레이터 CLI](https://developer.android.com/studio/run/emulator-commandline) | 화면 없는 실행과 가상 기기 사용 |

범용 리서치 스킬의 SKILL.md, clarification/research/software-structure/evaluation 참조와 프로젝트 공통 실행 지침도 읽었다. 개인 자료는 공개 웹 검색이나 외부 서비스에 업로드하지 않았다. 개인 원본은 변경하지 않았다.

## APK 분석

공식 배포 APK를 가상 기기에 설치하고 MacroDroid 소개 화면을 실행했다. 결제·로그인·Pro 활성화는 하지 않았다. 사용자가 겪은 결제 제한의 정확한 조건은 재현하지 않았다.

| 대상 | 확인 |
|---|---|
| MacroDroid 6.2.0 베타 universal | 패키지 `com.arlosoft.macrodroid`, versionCode 602000000, targetSdk 36. 설치·소개 화면 실행 성공 |
| MacroDroid Helper 1.19 | 패키지 `com.arlosoft.macrodroid.helper`, versionCode 19, targetSdk 21. 다운로드·정적 분석만 수행; 설치하지 않음 |
| 분석 도구 | JADX 1.5.6, aapt2 36.0.0 |

본체 `SystemSettingAction`의 global 분기에서 `Settings.Global.putInt/putFloat/putLong/putString` 호출과 `SecurityException` 처리의 `WRITE_SECURE_SETTINGS` 권한 안내를 확인했다. 보조 앱 `CommandReceiver`의 global 분기에서도 같은 설정 API와 권한 요구를 확인했다. 이것은 해당 기능의 구현 경로에 관한 정적 근거다. 모든 기능·난독화 코드·결제 구조를 분석했다는 뜻은 아니다.

JADX는 본체 단일 클래스 처리에서 오류 수 1, 보조 앱 전체 처리에서 오류 수 75를 보고했다. 위에서 확인한 생성 파일의 관련 분기는 읽을 수 있었지만 전체 디컴파일 성공으로 처리하지 않는다. 독립 구현의 실행 검증을 별도로 수행했다. 제3자 코드를 앱 소스에 복사하지 않았다.

분석 원문은 Git 제외 `work\android-lab\SystemSettingAction.java`, `helper-analysis\sources\com\arlosoft\macrodroid\helper\CommandReceiver.java`, `source-2.txt`에 있다.

SHA-256:

- MacroDroid: `98da626f195f1e5c323973fb9bcb00a794ed4588cbb8da3cf710be577e489aa6`
- Helper: `4467924de678819006405d3cbdff5f7636225d77cd4cbc8bd77835173a33099b`
- Blink Link 최종 APK: `faf99ba69f2cda7ef574413902ffadc1167f23cb47fa437e1d263380caabbd66`

## 실행 검증

환경은 전용 `BlinkLink16` AVD, `emulator-5580`, Android 16 API 36 Google APIs x86_64 r07, emulator 37.3.9, WHPX다. `-no-window -no-audio -no-snapshot`으로 실행했고 GUI 입력은 `adb -s emulator-5580 shell input`으로 게스트에만 전달했다. Windows GUI 테스트를 호스트에 대신 실행하지 않았다. 기존 물리 기기의 연결은 없었다.

| 검사 | 결과 |
|---|---|
| 정책 검사: 중지·권한 없음·Wi-Fi 없음·미등록·SSID 누락/null·다른 이름·대소문자·이미 켜짐·켜기 | 10/10 통과 |
| APK 빌드 및 서명 | Java 17 / API 36 빌드, v3 서명 검증 통과 |
| 최초 준비 부족 상태 | 시작 대신 준비 안내 표시 |
| Android 최초 네트워크 허용 | 허용 전 설정값 0, 명시적 허용 후 1 확인 |
| 앱 업데이트 후 감시 재개 | 통과 |
| 앱을 홈으로 내린 후 꺼짐 복구 | 통과. 첫 폴링에서 1 확인; 0.0초 기록은 폴링 해상도 결과이지 지연 0 보장이 아님 |
| Wi-Fi 꺼짐 | 꺼진 동안 무선 디버깅 값 0 유지 |
| Wi-Fi 재연결 | 4.2초 후 설정값 1 확인 |
| 일시정지 | 33초 이상 자동 켜기 없음 |
| 감시 재개 | 다시 켜짐 |
| 위치 꺼짐으로 SSID 확인 불가 | 33초 이상 자동 켜기 없음 |
| 위치 다시 켜기 | 복구 성공 |
| 실제 AVD 재부팅 | 재부팅 명령부터 33.1초 후 설정값 1, foreground 서비스 확인. 앱 화면을 다시 열기 전에 확인 |
| 설치 스크립트 | 전용 AVD에서 설치 및 명시적 권한 부여 실행 성공 |
| 화면 | 초기 상태·허용 창·복구 완료·재부팅 후 화면 PNG 확인. 큰 버튼과 한글 표시 확인 |
| 충돌 | 최종 부팅의 crash 버퍼가 비어 있음. 모든 시점·모든 기기에서 충돌 없음의 보장은 아님 |

첫 시험에서는 네트워크 허용 창 대기 중 재시도 횟수가 소진돼 이후 복구가 늦어졌다. 성공 시 횟수 초기화, 설정 변경 감시, 요청 간 최소 5초 간격으로 수정하고 위 회귀 검사를 통과했다.

JSON 결과, 스크린샷, XML UI 덤프, 서비스 확인은 `work\android-lab`에 보존했다. `android\tests\lab_ui.py`는 새 설치의 준비 검사, `emulator_regression.py`와 `emulator_reboot.py`는 권한·Wi-Fi 등록을 마친 전용 AVD 검사다. 하드코딩된 `emulator-5580`만 대상으로 하며 호스트 입력을 사용하지 않는다. 보존본 Python 구문 검사는 통과했고, 실행 결과는 보존 전 동일 동작의 `work` 스크립트에서 얻었다.

## 남은 실기 확인

S23 Ultra에 설치하여 최초 권한 부여와 Wi-Fi 허용을 마친 뒤 재부팅·잠금 해제·Wi-Fi 재연결·절전 복귀·scrcpy 연결을 확인해야 한다. 삼성 One UI 정책에 따라 추가 제한이 있을 수 있다. 현재 증거만으로 휴대폰을 전혀 만지지 않아도 되는 완전 무인 연결을 보장하지 않는다.

파일 관리자 열기 명령은 실행하지 않았고 표시 여부도 확인하지 않았다. 외부 업로드·발송·유료 결제는 하지 않았다.

검사 종료 후 이 작업이 만든 `emulator-5580`만 정상 종료했다. AVD 디스크와 시험 자료는 유지했다. 기존 PC GUI 수정과 `tests\vmware\recording` 작업은 변경하지 않았다.
