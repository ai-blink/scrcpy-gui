# Blink Link 0.3.1 리뷰 수정

2026-11-11. 0.3.0의 세 서브에이전트 리뷰에서 확인한 제품 결함 7건과 검사 허점 1건을 수정했다. S23 Ultra 실물 기기에는 설치하거나 설정을 변경하지 않았다.

## 수정과 재현 검사

| 리뷰 항목 | 변경 | 회귀 근거 |
|---|---|---|
| P1 음성 재실행 영구 대기 | 실제 런타임에서 사용하는 SpeechSessions로 고유 UUID·완료/실패/취소별 타이머 해제. 오래된 콜백은 소유 세션에만 전달 | 실제 helper의 가상 시계 검사: 정상 완료 A의 오래된 timeout/error가 B를 방해하지 않음, 중복 완료/timeout/취소/clear |
| P2 예약 5번째 하루 누락 | 날짜를 실행 수용 시점에만 저장. 동시 최대4개 초과분은 같은 날 감시 중 대기, 완료 시 다음 예약 시작 | Android 서비스에서 같은 시각의 대기3초→알림 5개. 5번째 대기 중 날짜 없음 및 다섯 개 완료 |
| P2 감시 버튼 역동작 | 버튼 참조 유지, 실제 상태로 문구·tag 갱신. 화면에 보인 상태와 실제 상태가 다르면 재확인 안내, 지연 list 재생성 제거 | 실제 UI 시작→중지→시작 문구 검사 |
| P2 자기 백업 복원 불가 | 저장/내보내기/가져오기와 문서 읽기에 공유16MiB UTF-8 바이트 상한. 저장 전에 복원 가능한 내보내기 형태까지 검증 | 이전256KB를 넘는 한글6개 roundtrip, 최대100×16×1000 JSON escape roundtrip, byte초과 거절·기존자료 보존 |
| P2 알림 독립 진입의 연결 복귀 | MainActivity CLEAR_TOP/SINGLE_TOP 명시 이동 | MainActivity 없는 새 task의 MacroActivity에서 연결 버튼→MainActivity 확인 |
| P2 동작 입력 초안 유실 | 열린 동작 대화상자의 index/type/value를 Bundle에 저장·복원. 창 해제 및 스크롤 지원 | 미적용 음성 문구를 입력하고 다크 테마 전환으로 Activity 재생성 후 종류/값 확인 |
| P3 긴 이름 복제 불가 | 접미사 포함80자, UTF-16 surrogate pair 경계 보존 | 80자 원본과 경계 emoji 복제 이름 검증 |
| P3 삭제/순서 검사 허점 | 저장 후 다시 열어 첫 동작의 종류/값 확인. 삭제 후 프로세스 재시작·목록 전체에서 부재 확인 | 강화한 UI 회귀 스크립트 |

## 산출물

- versionCode 5 / versionName 0.3.1.
- APK: `app/android/BlinkLink-0.3.1-debug.apk`, 기존 개발 서명 키 유지.
- SHA-256: `47f8bd9336517d03026480d964ff016dfc62c1e7ecf7006653ec57c8f6d95735`.
- 재시도 정책/예산 검사24건과 SpeechSessions 회귀8건, APK v3 서명 검증을 빌드에서 실행한다.
- `android/tests/build-instrumentation.ps1` → `python android/tests/run-instrumentation.py`로 별도 시험 APK를 실행한다. 제품 APK에 테스트 클래스·가짜 엔진을 넣지 않는다.
- UI 실행: `python android/tests/emulator_macros.py`. 실제 Android 렌더링 PNG/XML과 결과는 `work/android-lab/review-031/`에 남긴다.

## 범위와 한계

전용 Android16 AVD BlinkLink16 / emulator-5580, 창 없는 실행만 사용했다. 매 ADB 조작 전에 대상 이름/qemu/package를 확인한다. 실제 음성 엔진·스피커 청취는 이 회귀의 범위가 아니다. 음성 경합은 제품과 같은 SpeechSessions 코드에 늦은 완료/실패/타이머를 주입해 검증한다. Samsung 절전·실물 네트워크 및 문서 제공자별 UI 수락 검사는 별도다.

추가로 앱 전체 알림이 허용돼도 매크로 실행 채널만 차단된 경우를 확인해, 보이지 않는 알림/앱 열기를 완료로 기록하지 않고 실패 처리하도록 보완했다.

## 실제 결과

최종 APK에서 Android instrumentation 38개 assertion, UI 9개 시나리오 모두 통과했다. 정책/예산24건 + 실제 SpeechSessions 회귀8건 + 대상 보호 모의 검사3건도 통과했다. APK 버전0.3.1과 해시를 확인했고, crash 버퍼에 앱 충돌은 없었다. 게스트 표시 설정(밝은 테마, 글자1.0)을 복원한 뒤 전용 에뮬레이터만 종료했다. 음성/예약 수정은 별도 서브에이전트가 다시 읽어 새 확정 회귀가 없음을 확인했다.

미리보기: `app/android/BlinkLink-0.3.1-draft-preview.png`는 테마 전환 후 실제 복원된 동작 설정 화면이다.
