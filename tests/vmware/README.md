# VMware background validation

이 PC의 Windows VM에서 `scrcpy-gui`, `key-demo-osk`, `new-alt/next`를 검사한다.
VMware 기본 콘솔을 열지 않고 `vmrun ... start ... nogui`와 VMware Tools 게스트
작업만 사용한다. 호스트에 입력을 주입하거나 창을 활성화하는 코드는 없다.

## 반복 실행

프로젝트 루트에서 PowerShell 7로 실행한다.

```powershell
./tests/vmware/Invoke-VMwareValidation.ps1
```

로컬 기본 경로는 `work/vmware-background/Background-Test.vmx`다. 실행기는 VMX의
USB, 네트워크, HGFS, 공유 클립보드, 드래그 전송 차단을 확인하고, 필요하면 VM을
화면 없이 시작한다. 전용 TestAgent 계정의 로그인과 1920×1080 게스트 화면을
준비한 다음, 매번 고유한 실행 ID로 결과를 만든다.

`guest-credentials.json`과 `guest-admin-credentials.json`은 이 VM만의 시험 자격
증명이다. 둘 다 Git에서 제외되는 `work`에 보관한다. 호스트 계정 정보를 넣지 않는다.
다른 VM을 사용하려면 `-VmPath`, `-CredentialFile`, `-AdminCredentialFile`을 지정한다.

## 게스트 준비와 검사 구조

- 완전 복제한 Windows 11 VM을 사용한다. 원본 VM과 디스크를 공유하는 linked clone이 아니다.
- USB 컨트롤러와 네트워크는 꺼져 있다. 호스트 폴더를 공유하지 않고 읽기 전용
  `BACKGROUND_TEST` ISO로 앱·런타임·테스트를 전달한다.
- `Guest-Unpack.ps1`은 ISO를 게스트의 `C:\BackgroundLab`에 푼다.
  `Guest-SourceLayout.ps1`은 소스 경로를 읽는 계약 검사에 필요한 스냅샷을
  게스트의 `C:\ai\projects`에 배치한다. 이는 호스트 공유 폴더가 아니다.
- `Guest-Setup.ps1`은 복제본에서 전용 시험 계정과 자동 로그인을 준비한다.
  `key-demo-osk`와 `new-alt`의 관리자 권한 매니페스트를 실행하려면 **게스트 안에서만**
  시험 계정을 Administrators에 추가하고 새 로그인 토큰을 사용해야 한다.
- `Guest-LaunchProbe.ps1`은 게스트 작업 스케줄러의 전용 작업으로 실행한다.
  호스트 UAC를 조작하지 않는다.
- `Guest-Run.ps1`은 기존 new-alt `BackgroundTestDesktop.cs` 실행기를 VM 안에서
  재사용해 각 테스트를 별도 Windows 데스크톱에 격리한다. 원본 helper의 로컬 복사본은
  Windows PowerShell 5.1 컴파일러가 읽도록 `out var` 문법만 풀어썼다.
- scrcpy 회귀 실행기는 자식 프로세스 시험을 위해 DLL 대신 원래 EXE로 실행한다.
- `Guest-Probe.ps1`은 별도의 새 프로세스로 세 앱의 창·응답 상태를 확인하고 게스트
  전용 WinForms 입력창에 커서 이동·클릭·문자 입력을 수행한다.

앱 산출물은 표준 빌드 출력의 복사본이며 SHA-256 목록은 로컬 payload의
`manifest.json`에 있다. 사용자 학습 DB, 로그, 개인 설정은 복사 대상에서 제외했다.
기존 빌드 산출물의 검증이며 다른 프로젝트를 새로 빌드하거나 호스트 실행본을
교체하는 작업은 하지 않는다.

## 결과와 판정

호스트 결과는 `work/vmware-background/evidence-*`에 저장된다. 테스트 로그,
게스트 앱 스크린샷, 입력 수락 결과와 호스트 관찰 JSON을 함께 확인한다.

호스트 관찰은 foreground PID와 커서 위치를 읽기만 한다. 사용자가 움직인 커서를
실패로 세지 않으며, VM 프로세스가 호스트 foreground가 된 표본 수를 따로 기록한다.
한 번의 표본 관찰을 모든 환경에서의 간섭 0% 보장으로 해석하지 않는다.

실제 휴대폰 미러링, USB 컨트롤러, EyeTech 장치, 게임 반응, 선택형 외부 ML 서비스와
음성 native fixture는 이 VM의 기본 검사 범위와 구분한다. 건너뛴 검사는 로그에 남는다.


준비된 스냅샷은 `projects-background-ready-20261103`이며 검증 후 VM은 정상 종료했다.
실패한 제품 검사가 남으면 실행기는 종료 코드 1을 유지한다. 이는 입력 격리 검사와
제품 회귀 검사의 상태를 함께 보존하기 위한 것이다. 최종 기록은
`notes/VMWARE-BACKGROUND-VALIDATION-2026-11-03.md`를 참고한다.


## 2026-11-04 비교 사전검사

`Invoke-Preflight20.ps1`은 guest UUID·nonce·input desktop을 고정한 synthetic 20개와
별도 `Observe-Host.ps1`을 실행한다. Unicode 진단은 IME 시험이 아니며 호스트 입력
누출은 미측정이다. observer는 키 내용·창 제목·클립보드 원문을 읽지 않는다.

QEMU 준비: `Start-QemuComparison.ps1`, `bcu_qemu.py`의 status/preflight/shutdown.
현재 QGA helper 누락으로 guest-exec는 실패하며 QEMU 입력 검사는 미실행이다.
Hyper-V 준비: 관리자 PowerShell의 `Prepare-HyperV.ps1 -EnableFeatures`(자동 재부팅 없음),
그 뒤 기능·권한이 준비되면 `New-HyperVComparison.ps1`로 별도 Gen1 VM을 생성한다.
기존 VM과 원본 디스크를 덮어쓰지 않는다. 비교용 디스크와 로컬 식별자는 work 아래에 있다.
상세 상태는 `notes/BCU-COMPARISON-2026-11-04.md`를 참고한다.

재부팅 후 관리자 PowerShell에서 `Invoke-HyperVPreflight20.ps1`을 실행하면
별도 VM 생성·부팅, PowerShell Direct 연결, UUID 고정, guest 20개 검사 및 호스트 관찰을
진행한다. 기존 VM은 로컬 identity.json의 VM ID·디스크·구성이 일치해야 재사용한다.
콘솔을 열거나 호스트 입력을 주입하지 않는다. 결과는
`work/bcu-comparison/hyperv/preflight-*`에 저장한다. VM은 검사 후 실행 상태로 남는다.

QEMU 대체 경로: Guest-StageQemuPreflight.ps1로 승인된 준비 복제 VM에 nonce와
QEMU UUID를 고정한 로그인 작업을 등록하고, 종료된 디스크를 별도 qcow2로 변환한다.
Invoke-QemuStagedPreflight.ps1은 staged-run.json 및 변환 이미지로 한 번 실행하고
호스트 관찰·QGA 파일 회수·QEMU 종료 요청을 수행한다. collect-staged는 guest-exec가
필요 없지만 매번 새 nonce와 준비 이미지가 필요하다. 기존 결과 폴더를 재사용하지 않는다.

## 200개 × 3회 작업 완료 시간 측정

VMware: `Invoke-Preflight20.ps1 -Benchmark`.
Hyper-V: 관리자 PowerShell에서 `Invoke-HyperVPreflight20.ps1 -Benchmark`.
QEMU: `Guest-StageQemuPreflight.ps1 -Benchmark`로 새 nonce를 준비하고 정상 종료한
복제 디스크를 windows-benchmark-staged.qcow2로 변환한 뒤
`Invoke-QemuStagedPreflight.ps1 -Benchmark`를 실행한다. 기존 이미지는 덮어쓰지 않는다.
후보를 동시에 측정하지 않는다. 각 후보는 동일 세션에서 200개씩 3회 연속 실행한다.
`python tests/vmware/summarize_benchmark.py`는 receipt를 검증하고
work/bcu-comparison/benchmark-200x3.json 및 notes/BCU-BENCHMARK-200X3.md를 갱신한다.
측정값은 고정 Pump 대기를 포함하므로 순수 입력 지연이나 하이퍼바이저 속도 순위가 아니다.
