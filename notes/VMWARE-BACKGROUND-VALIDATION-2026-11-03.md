# VMware Background Computer Use 검증 — 2026-11-03

호스트 사용자의 마우스·키보드 작업과 분리된 Windows VM에서 scrcpy-gui,
key-demo-osk, new-alt/next를 실행하고 검사했다. VMware 기본 콘솔이나 호스트
입력 주입을 사용하지 않았다. 반복 실행기는 `tests/vmware/Invoke-VMwareValidation.ps1`이다.

## 완료 기준과 범위

- 완료 기준: 별도 VM 구성, 세 앱 실행·회귀 검사, 게스트 클릭/문자 입력 수락,
  호스트 포커스·커서 읽기 전용 관찰과 재실행 가능한 결과 파일.
- 수락 검사: USB/네트워크/공유 폴더/클립보드 차단, nogui 실행, 테스트 데스크톱 분리,
  실제 게스트 입력창의 텍스트 수락, VM이 호스트 foreground가 된 표본 수.
- 범위: 기존 표준 빌드 산출물의 격리 검증. 호스트 앱 재배포, 제품 코드 수정,
  실제 휴대폰·게임패드·EyeTech·게임 수락은 포함하지 않는다.
- 리뷰 한도: 환경·경로·권한 전제조건을 정리하고 실패를 재현한다. 제품 결함을
  검증 과정에서 임의로 수정하지 않는다.
- 중지 조건: VMX 격리 설정 불일치, VMware GUI 콘솔 실행, 게스트 세션 준비 실패,
  시간 초과는 실행기를 실패로 종료시킨다. 테스트 실패를 통과로 바꾸지 않는다.

## 환경

- 설치된 VMware Workstation Pro: 26.0.1 build 25688693.
- Windows 11 Pro x64 기존 검증 VM의 full clone. 신규 클린 설치나 linked clone이 아니다.
- 로컬 VM: `work/vmware-background/Background-Test.vmx`, 4 vCPU / 8 GiB RAM.
- 전용 TestAgent 계정. 두 앱의 requireAdministrator 매니페스트 때문에 이 복제 VM
  안에서만 관리자 그룹과 최고 권한의 전용 작업 스케줄러 작업을 사용한다.
- 게스트 해상도 1920×1080, .NET 8.0.33 / 9.0.22, 테스트 CLI SDK 9.0.320.
- USB·USB xHCI·네트워크·HGFS·공유 클립보드·드래그 전송 차단.
- 읽기 전용 ISO로 payload 전달. 게스트 C:\ai\projects는 게스트 디스크의 복사본이며
  호스트 프로젝트 폴더 마운트가 아니다.
- 호스트 계정·UAC·안구마우스·로그인 설정을 변경하지 않았다.

## 회귀 결과

| 대상 | 결과 |
|---|---|
| scrcpy-gui | 1,757 assertions PASS, WPF 렌더 포함 |
| key-demo-osk OSK suite | 886 PASS / 0 FAIL / 1 SKIP |
| new-alt Core | 540 PASS / 0 FAIL |
| new-alt App 전체 실행 | 993 PASS / 3 FAIL / 1 SKIP |
| new-alt 실패 3건 후속 재검사 | 소스 이미지 제공 후 2 PASS / 프로필 배치 1 FAIL 재현 |

전체 실행 근거: `work/vmware-background/evidence-20261103-234102`.
후속 재검사 근거: `work/vmware-background/evidence-20261103-234758`.

new-alt App의 전체 실행을 통과로 보고하지 않는다. 첫 전체 실행에서 소스 파일을 직접
읽는 두 자산 검사의 PNG가 빠졌고, 자산 제공 후 해당 두 검사는 통과했다. 남은 실패는
`OverlayProfileManagementTests.ProfileBoardOpensTheSelectedProfileDrawerAndShowsThreeColumnsAndRowsAtMinimumSize`:
프로필 창 860×540 DIP에서 완전히 보이는 행이 기대 3행 이상에 못 미치는 2행이다.
1920×1080 게스트에서도 재현됐다. 제품 소스는 변경하지 않았다.

OSK의 외부 실제 ML 모델 통합 검사와 new-alt의 native 음성 fixture 검사는 각각 1건
건너뛰었다. OSK 스크린샷에는 선택형 Python 미설치 경고가 있으며, 기본 키보드 창은
정상적으로 표시됐다. key-demo-osk Core suite 전체 실행을 수행했다고 주장하지 않는다.
new-alt의 ViGEm 드라이버 및 실제 입력 장치는 이 VM에 설치·연결하지 않았다.

## 앱과 격리 관찰

세 앱 모두 게스트에서 살아 있는 응답 가능한 프로세스와 실제 창 스크린샷을 확인했다.
OSK와 new-alt는 NoActivate/오버레이 구조여서 Process.MainWindowHandle이 0이어도
창이 실제로 보일 수 있다. 반복 실행기는 PID별 보이는 창 수를 별도로 확인한다.
앱 복사본의 SHA-256은 payload/manifest.json과 apps.json에 보존한다.

전체 실행 및 입력 probe 동안 호스트 5,794개 표본에서 VMware foreground 0건,
호스트 입력 주입 호출 0건, 호스트 창 활성화 호출 0건이었다. 그동안 호스트 커서가
변한 표본은 3,970개로, 사용자의 움직임을 실패로 세거나 에이전트의 움직임으로
단정하지 않았다. 게스트 입력창은 합성 문자열을 실제로 수락했고 게스트 foreground가
해당 입력창인 점을 확인했다. 이는 이번 관찰 범위의 결과이며 모든 환경에서 간섭 0%를
수학적으로 보장한다는 뜻이 아니다.

초기 전송은 VMware Tools의 큰 파일 복사가 느려 중단하고 읽기 전용 ISO로 바꿨다.
소스 경로를 사용하는 검사는 게스트 안에 같은 경로 구조를 만들어 해결했다.
Windows PowerShell에서 별도 데스크톱을 만든 뒤 같은 프로세스로 UI probe를 이어
실행하지 않고, 새 게스트 작업으로 분리한다. 산출물·자격 증명·VM 디스크는 work 아래에
있으며 Git에서 제외한다.


## 최종 입력·창 검증과 보존 상태

최종 도구 실행 근거는 `work/vmware-background/evidence-20261103-235019`다.
앱별 보이는 창 수는 scrcpy-gui 1개, OSK 1개, new-alt 2개였고 세 프로세스 모두 응답했다.
합성 문자 수락 true, 게스트 foreground 입력창 일치 true, 실제 마우스 드래그로
18글자 선택을 확인했다. 이 실행의 호스트 320개 표본에서 VMware foreground 0건,
검증 실행기의 호스트 입력/활성화 API 호출 0건이었다. 호스트 사용자가 커서를 움직인
197개 변화 표본을 간섭으로 단정하지 않았다.

최종 실패 3건 재검사는 2 PASS / 1 FAIL로 이전 결과와 같았다. 실행기의 종료 코드 1은
재현된 프로필 배치 검사 실패를 보존한 것이며, 게스트 입력 격리와 앱 시작 검사의 실패가 아니다.

검증 후 복제 VM을 정상 종료하고 `projects-background-ready-20261103` 스냅샷 생성과
목록 조회를 확인했다. 현재 실행 VM은 0개다. 반복 실행기는 VM을 nogui로 시작하고
TestAgent 로그인 준비를 기다리며, 게스트 화면과 작업을 준비한다. 기존 유비키 VM과
호스트에서 사용 중인 앱은 종료·교체하지 않았다. 모든 PowerShell 도구 구문 검사와
scrcpy-gui의 diff 공백 검사를 통과했다.
