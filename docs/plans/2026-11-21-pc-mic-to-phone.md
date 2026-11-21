# PC 마이크를 휴대폰 마이크로 쓰기 — 검증 결과와 상세 계획

- 작성: 2026-11-22 (검증 2026-11-21~22)
- 대상: 갤럭시 S23 Ultra(SM-S918N), Android 16 / One UI 8.5, 무선 디버깅 연결
- 근거: scrcpy PR [#7004](https://github.com/Genymobile/scrcpy/pull/7004) (열림, scrcpy 5.0 기반, 커밋 `5168ef93`)

## 1. 목표와 범위 (2026-11-21 합의)

| 항목 | 결정 |
|---|---|
| 1차 용도 | (a) 구글·Gemini 음성 명령, (d) 받아쓰기(검색창·메시지 입력) |
| 제외 | 일반 전화 통화 — 필요하면 Windows '휴대폰과 연결'(블루투스) |
| 순서 | 검증 먼저 → 결과로 상세 계획 |
| 실패 시 대안 | 그때 정함 |
| 보낼 PC 소리 | Voicemeeter Potato에서 처리된 목소리(`Voicemeeter Out B1`). ASIO(Insert Virtual ASIO)는 FFmpeg DirectShow가 열 수 없고 DAW가 점유하므로 쓰지 않음 |
| 받아쓰기 엔진 | 로컬 faster-whisper `large-v3-turbo`(GPU), 한국어 고정. 종량 API 금지 |
| 받아쓰기 시작 | 누르고 있는 동안만 듣기 |
| 받아쓰기 입력 | 검증 단계는 클립보드 + scrcpy 화면 Ctrl+V |

## 2. 검증 결과

### 2.1 (a) 음성 주입 — 통과

PR #7004 수정판이 폰에서 `AudioPolicy`(shell 권한, `MIX_ROLE_INJECTOR` + `ROUTE_FLAG_LOOP_BACK`)를 등록해 마이크 녹음에 PC 소리를 끼워 넣는다. 등록 기록: `dumpsys audio` → `registerAudioPolicy … u/pid:2000/… Mix:0-Typ:r-Rul:7`.

| 단계 | 방법 | 결과 |
|---|---|---|
| 셸 녹음 | 시험 wav를 반복 주입, `--audio-source=mic --record` | 원문 그대로 녹음(Whisper 대조) |
| 삼성 음성 녹음 앱 | 같은 주입, adb로 녹음 시작·정지 | 원문 그대로 녹음 |
| 구글 음성 검색 → Gemini | "오늘 서울 날씨 알려 줘" 주입 후 `android.speech.action.WEB_SEARCH` | Gemini 창이 서울 날씨로 답함 |
| 녹음 종류 6가지 | `--audio-source` = mic / mic-unprocessed / mic-camcorder / mic-voice-recognition / mic-voice-communication / voice-performance | 6가지 모두 원문 그대로, 크기 동일(-24.6dBFS) |
| 끈 뒤 복구 | 주입 종료 → `unregisterAudioPolicy` 확인 → 공식 4.1로 마이크 녹음 | 방 소리가 정상으로 잡힘(내장 마이크 복귀) |
| 실제 PC 마이크 | `audio=Voicemeeter Out B1(VB-Audio Voicemeeter VAIO)` | 장치 열림·주입 시작 확인. **사람이 말하는 Gemini 실사용 확인은 미완** |

바뀌지 않는 것: 일반 전화(통화 경로 별도), "Hey Google"·"하이 빅스비" 호출어(폰 저전력 칩), 화면 녹화 내부 소리.

삼성 위험: 이전 개발안 #6439에서 S25 Ultra가 "내장 마이크가 계속 쓰인다"고 보고됐으나, 이 폰에서는 재현되지 않았다.

### 2.2 (d) 받아쓰기 — 통과(엔진)

| 항목 | 결과 |
|---|---|
| GPU | RTX 5090, ctranslate2 4.9.0 CUDA 동작 |
| 속도 | 9.1초 문장 0.19초(데움 뒤). 새 프로세스의 첫 인식은 약 45초(새 GPU 세대용 커널 준비) — 시험 창은 시작할 때 미리 치름 |
| 정확도 | 시험 문장(TTS) 원문과 같음. 실제 목소리 품질은 사용자 확인 대기 |

### 2.3 소리 크기 (dBFS, 100ms 단위 RMS)

| 측정 | 평균 | 말할 때(상위 5%) | 최대 |
|---|---|---|---|
| Voicemeeter Out B1 실제 목소리 | -50.5 | -37.9 | -34.3 |
| Zen Q 입력 1/2(처리 전) | -47.3 | -34.3 | -30.8 |
| 주입 시험 음성(폰에서 녹음) | -24.6 | — | — |
| 주입 끈 뒤 폰 내장 마이크(말 없음) | -50.6 | — | -29.4 |

B1 목소리는 음성인식 권장(말할 때 평균 약 -20dBFS)보다 15~20dB 작다. Voicemeeter에서 B1 출력·입력 게인을 올려야 한다.

### 2.4 시행착오 (다음 작업자가 다시 밟지 않도록)

- PR 안내의 `--client-audio-source=default`는 Windows에서 `Malformed dshow input string`으로 실패한다. `audio=<장치 이름>`을 써야 한다(`--list-client-audio-sources`가 이름을 준다).
- 파일 주입은 `file://C:/경로/파일.wav`(슬래시 두 개). `file:///C:/…`는 열지 못한다.
- 공식 Windows 빌드의 FFmpeg에는 wav 읽기가 없다. 시험용으로 `--enable-demuxer=wav`를 켜서 빌드했다(`scripts/pc-mic/build-scrcpy-mic.ps1`).
- 수정판 폴더의 adb는 버전이 달라, 그대로 쓰면 공용 adb 서버가 재시작돼 기존 연결이 끊긴다. 실행 시 `ADB` 환경 변수로 앱이 쓰는 adb(4.1 폴더)를 지정한다.
- B1~B3가 완전한 0이면 Voicemeeter 입력 줄의 B 버튼이 꺼진 것이다.
- faster-whisper 1.2.1은 PyAV 16 이상과 맞지 않는다(`metadata_errors` 오류). `av<16`으로 고정.

## 3. 지금 들어간 것 (2026-11-22)

- scrcpy-gui **소리 → PC 마이크 → 폰** 칸(`--client-audio-source`). 앱을 켤 때 수정판에 PC 녹음 장치 목록을 물어 채운다.
- 이 칸을 고르면 그 실행만 수정판(`C:\app\scrcpy-mic*\scrcpy.exe` 또는 데이터 폴더 `scrcpy-mic\`)으로 실행하고 `ADB`를 고정한다. "(기본)"이면 기존 공식 scrcpy.
- 수정판 빌드 스크립트: `scripts/pc-mic/build-scrcpy-mic.ps1`
- 받아쓰기 시험 창: `scripts/pc-mic/stt_window.py` (전용 venv `C:\dev\venvs\scrcpy-gui-py313`, `pythonw`로 실행)
- 측정 도구: `scripts/pc-mic/bus_probe.py`(장치별 소리 크기), `scripts/pc-mic/stt_bench.py`(받아쓰기 속도)

코드: `src/ScrcpyGui/MainWindow.ClientAudio.cs`, `src/ScrcpyGui/MainWindow.xaml.cs`(옵션 정의·시작 시 목록·실행 파일 선택).

## 4. 상세 계획

### 단계 1 — 실사용 확인 (사용자, 다음 세션 시작 전)

1. Voicemeeter B1 음량을 올려 말할 때 약 -20dBFS로 맞춘다(`bus_probe.py 10 --wait`로 측정).
2. scrcpy-gui에서 B1을 고르고 실행 → 삼성 음성 녹음 앱 파형으로 확인:
   - PC 마이크에 말하면 파형이 움직인다.
   - 폰 마이크 구멍을 톡톡 쳐도 파형이 거의 안 움직인다(내장 마이크가 빠짐).
   - Voicemeeter에서 음소거하면 파형이 평평하다.
   - 창을 닫은 뒤 톡톡 치면 파형이 크게 움직인다(복구).
3. Gemini 마이크로 실제 명령이 인식되는지, 받아쓰기 창 결과가 정확한지 확인한다.

완료 조건: 위 네 가지 파형 확인 + Gemini 명령 1회 성공 + 받아쓰기 3문장 정확.

### 단계 2 — 마이크 옵션 다듬기 (scrcpy-gui)

| 작업 | 내용 |
|---|---|
| 장치 이름 | 목록에 `audio=` 접두어 없이 이름만 보이게 하고, 실제 인자에는 붙인다 |
| 상태 표시 | 실행 중 "PC 마이크 → 폰 전달 중" 표시. 폰이 주입을 거부하면(scrcpy가 클라이언트 오디오만 끄고 계속 실행) 로그 문구를 잡아 상태 줄에 알린다 |
| 버전 확인 | Android 13 미만이면 칸을 끄고 이유를 보인다 |
| 수정판 배포 | 수정판을 데이터 폴더 `scrcpy-mic\`로 함께 배포할지 결정(배포 크기·라이선스 표기·업데이트 방법) |
| 음량 | 받아쓰기 창 또는 GUI에 실시간 dB 막대(목표 구간 표시) — 사용자 원하면 |
| 시험 | 인자 조립(옵션 선택 시 `--client-audio-source=audio=…`), 실행 파일 선택(수정판 없으면 실행 안 함), `ADB` 고정을 단위 시험에 추가 |

### 단계 3 — 받아쓰기를 scrcpy-gui에 넣기

결정할 것(사용자):

1. **엔진을 붙이는 형태**
   - (가) Python faster-whisper를 백그라운드 프로세스로 띄움 — 지금 검증한 그대로, 대신 venv(CUDA 라이브러리 포함 수 GB)를 배포해야 함
   - (나) whisper.cpp CUDA 빌드(실행 파일 + 모델)를 C#에서 호출 — 배포가 단순, 품질·속도 재측정 필요
   - 권장: 개인 사용이면 (가)로 먼저, 배포를 생각하면 (나)
2. **시작 방법**: 전역 단축키(누르고 있는 동안) / 조작판 드웰 버튼 / 둘 다
3. **글자를 넣는 방법**
   - 클립보드 + Ctrl+V(지금 방식, 폰 코드 변경 없음)
   - Blink Link에 접근성 서비스를 추가해 입력창에 바로 넣기(완전 자동, 접근성 권한 필요)
   - Blink Link 키보드(IME) — 키보드 전환이 필요해 비권장

완료 조건: 버튼 하나로 말하기 → 폰 입력창에 글자 입력까지 사람 손 2회 이하.

### 단계 4 — 공식 반영 추적

- PR #7004가 병합되면 공식 scrcpy로 바꾸고 수정판·빌드 스크립트를 정리한다.
- 병합 전에는 PR 갱신 시 `build-scrcpy-mic.ps1`로 다시 빌드하고 2.1 시험(셸 녹음·삼성 녹음·6가지)을 다시 돌린다.

## 5. 위험

| 위험 | 대응 |
|---|---|
| 목소리가 작아 인식률 저하 | 단계 1에서 B1 게인 조정 |
| 비공식 수정판 의존 | 기본 실행은 공식 scrcpy 유지, 옵션 선택 시에만 수정판 |
| One UI 업데이트로 정책 거부 | 거부 시 scrcpy가 클라이언트 오디오만 끄므로 화면·조작은 유지, 상태 표시로 알림(단계 2) |
| 주입 중 폰을 직접 쓰면 내장 마이크가 안 들림 | 창을 닫으면 즉시 복구됨을 확인. 상태 표시로 켜져 있음을 알림 |
| Whisper 첫 실행 45초 | 프로그램 시작 시 미리 데움 |
