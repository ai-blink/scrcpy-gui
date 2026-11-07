# Background Computer Use 比較 — 2026-11-04

이번 작업은 첨부 연구의 권고 중 사용자가 선택한 VMware 관찰기·20개 사전검사와
Hyper-V/QEMU 비교 환경 준비를 구현한 것이다. 첨부문의 sandbox ZIP/HTML을
확보·실행했다고 주장하지 않는다.

| 후보 | 실제 확인 | 남은 조건 |
|---|---|---|
| VMware | synthetic 사전검사 20/20 통과, UUID·nonce·input desktop 대조 | IME·키 홀드·호스트 입력 누출·200×3 비교 미측정 |
| QEMU/WHPX | 독립 qcow2, Windows 부팅, QMP 이름/UUID 대조, COM1 QGA ping·파일 읽기 성공 | guest-exec helper 누락으로 검사 0/20 실행 |
| Hyper-V | 독립 80 GiB dynamic VHDX와 NoRestart 기능 준비·Gen1 생성 스크립트 작성 | 관리자 권한으로 기능 조회·활성화 및 실제 VM 생성·부팅 필요 |

## VMware 실제 결과

근거: `work/vmware-background/preflight-5be2e8c1522f4f59b24e8880a5639804`.
클릭 6, Unicode 진단 입력 4, 실제 휠 스크롤 4, 드래그 선택 3, 색상 표식 캡처 3이 통과했다.
paired-click은 수신 down 횟수 확인이며 모든 앱의 더블클릭 의미 검증이 아니다.
Unicode 주입을 한글 IME 검증으로 계산하지 않는다.

VMX SMBIOS 바이트에서 Windows GUID를 산출하고 게스트 UUID와 실행 nonce를 대조했다.
시험 thread desktop과 input desktop은 모두 Default였고 모든 동작 후 foreground도
fixture였다. 20개는 실제 세 앱 전체 수락이나 200개×3회 비교를 대체하지 않는다.

별도 호스트 관찰 프로세스: foreground WinEvent hook 설치 성공, 236표본,
foreground 이벤트 0, queue drop 0, 최대 표본 공백 46.305ms, 100ms 초과 공백 0,
관찰 약 7.438초. 클립보드는 sequence number만 읽고 원문·hash는 읽지 않는다.
키보드 내용·창 제목을 기록하지 않으며 호스트 입력·포커스 복원 API를 호출하지 않는다.
호스트 키/클릭/휠 누출과 원인 귀속은 미측정이므로 전체 격리 판정은 insufficient다.

동작별 guestLocalCompletionMs는 고정 Pump 대기를 포함한다. 순수 입력 수락 지연이나
하이퍼바이저 속도 우위를 뜻하지 않는다. 표식 픽셀 일치는 완전한 stale-frame 시험이 아니다.
첫 시도는 우클릭 기본 메뉴의 modal loop로 시간 초과됐다. 해당 기록을 보존하고
전용 fixture의 기본 메뉴를 비활성화한 재실행에서 20개를 통과했다.

## QEMU 실제 결과와 차단점

기존 설치 QEMU 11.1.0(v11.1.0-12130-ge470268ff4), WHPX, 4 vCPU/8192 MiB,
-display none, -nic none, loopback QMP 및 COM1 게스트 채널로 Windows를 부팅했다.
물리 USB passthrough·호스트 입력 폴백은 없다. 게스트 에이전트 11.1.0 ping과
파일 읽기가 작동했고, 회수한 Guest-Preflight20.ps1 SHA-256은 호스트와 일치했다:
`d5caaa76f12f807f48e6bfbe7be81eb916fa389c52cc6ad8b418f0eed4e6bb8c`.

하지만 guest-exec는 `Failed to execute helper program (No such file or directory)`로
실패했다. capture-output=false에서도 동일했다. GLib 2.88.3의 gspawn 보조 실행 파일이
기존 QEMU 배포에 빠져 있었다. 다른 host 디렉터리에서 발견한 helper는 읽기 권한이
없어 사용하지 않았다. stderr의 xsave state 경고 영향도 미측정이다.

공식 MSYS2 동일 버전 archive의 HEAD는 200이었다. 그러나 다운로드·추출과 VMware
시작을 묶은 후속 명령은 자동 승인 검토가 실행 전 거절했다. 제공된 이유는
`blocked by policy`뿐이다. 파일을 확보·검증·설치했다고 주장하지 않는다.
QEMU 입력 결과는 setup_failed, executed=0/not_run=20이다. 정상 종료 요청을 보냈고
현재 QEMU 프로세스가 종료된 것을 확인했다.

## Hyper-V와 필요한 관리자 작업

Windows 11 Pro, HypervisorPresent=true, QEMU WHPX 초기화는 확인했다.
Hyper-V 모듈과 vmms 서비스는 발견되지 않았다. 기능 상태 조회는 권한 상승 필요로
거절돼 Disabled로 단정하지 않는다. `work/bcu-comparison/hyperv/windows.vhdx`는
virtual size 80 GiB, dynamic VHDX, dirty-flag=false로 확인했다.

원본은 정상 종료된 BIOS/MBR Windows clone이다. Gen1 생성 스크립트는 4 vCPU,
고정 8 GiB, NIC 제거를 적용하며 기존 같은 이름의 VM을 덮어쓰지 않는다.
관리자 PowerShell에서 먼저 아래 스크립트를 검토·실행해야 한다.

```powershell
& 'C:\ai\projects\scrcpy-gui\tests\vmware\Prepare-HyperV.ps1' -EnableFeatures
```

자동 재부팅은 하지 않는다. 실제 RestartNeeded 결과를 확인한 뒤 다음 단계를 결정한다.
Hyper-V VM 생성·PS Direct·입력·성능은 현재 미실행이다.

## 도구·검증과 남은 범위

- Observe-Host.ps1: 이벤트+표본, gap/drop, cursor/clip, clipboard sequence, 미측정 범위.
- Guest-Preflight20.ps1 / Guest-LaunchPreflight.ps1: UUID·nonce·desktop 및 실제 수락 oracle.
- Invoke-Preflight20.ps1: VMware 실행과 결과 회수, 별도 observer 프로세스.
- Start-QemuComparison.ps1 / bcu_qemu.py: headless QMP/QGA, 이름·UUID 확인.
- Prepare-HyperV.ps1 / New-HyperVComparison.ps1: 관리자 점검·NoRestart 기능 준비·Gen1 생성.
- test_bcu_qemu.py: handshake, async event, 응답 ID 상관, 오류 전파 테스트 통과.
- 모든 PowerShell 도구 구문 검사 통과. Hyper-V 도구는 관리자 환경에서 미실행.

기계 판독 결과는 `work/bcu-comparison/comparison-status.json`에 있다.
기존 2026-11-03 세 앱 회귀 결과는 별도 근거이며 이 20개와 합산하지 않는다.
세 후보의 200×3 비교, p50/p95/p99 순위, 장시간 시험, IME·실장치 검증은 아직 수행하지 않았다.

근거 문서: [QEMU WHPX](https://www.qemu.org/docs/master/system/whpx.html),
[Microsoft PS Direct](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/powershell-direct),
[MSYS2 GLib 파일 목록](https://packages.msys2.org/packages/mingw-w64-x86_64-glib2).

## 2026-11-05 재부팅 후 Hyper-V 점검

Hyper-V 모듈 및 vmms Running을 확인했다. 현재 Codex 세션은 비관리자이므로
VM 조회·시작은 관리자 PowerShell에서 실행해야 한다.
사용자가 Invoke-HyperVPreflight20.ps1을 실행해 VM 생성에 성공했으나
windows.vhdx의 NTFS SparseFile 속성으로 Start-VM이 0xC03A001A를 반환했다.
VM ID는 73c28998-944e-4a95-ba07-19729c36db53이며 identity.json에 고정했다.
이 시도의 게스트 20개 검사는 미실행이다.

원인은 VHDX 내부의 dynamic 형식과 별개인 파일 시스템의 SparseFile 속성이다.
해당 테스트 디스크에만 fsutil sparse setflag <disk> 0을 적용했다.
내용 해시 검증 결과는 work/bcu-comparison/hyperv/sparse-repair.json에 저장한다.
두 Hyper-V 실행 스크립트는 SparseFile·Compressed·Encrypted 속성을 시작 전에
거부하도록 보완했으며 재시도는 동일 VM을 identity.json 대조 후 재사용한다.
속성 수정 후 실제 부팅 및 검사 성공 여부는 관리자 재실행 결과로 확인해야 한다.

재시도 preflight-28df1653a50c46e8b61f4b66cf052154에서는 VM 부팅 및 PowerShell Direct
연결, guest UUID 2e903a40-dd97-4884-9c93-b7aeabf338fe 대조와 도구 복사까지 성공했다.
게스트 세션의 실행 정책이 Guest-LaunchPreflight.ps1 로드를 거부하여 검사는 미실행이다.
런처를 게스트 자식 powershell.exe -ExecutionPolicy Bypass -File로 호출하도록 수정했다.
호스트·게스트의 영구 실행 정책은 변경하지 않으며 자식 종료 코드도 검사한다.
수정본 구문 검사 및 git diff --check는 통과했으나 실제 검사 결과는 재실행 전이다.

## 2026-11-05 Hyper-V 사전검사 최종 결과

`work/bcu-comparison/hyperv/preflight-bfc416f3ee70488a9a0a114d550cf9ff`에서
20개 실행·20개 통과·실패 0을 확인했다. run/summary/20개 receipt의 nonce와
guest UUID를 대조했으며 모든 receipt의 foregroundMatchesFixture가 true다.
desktop 및 inputDesktop은 Default다. 연결된 AVHDX에서 고정된 windows.vhdx까지의
부모 관계를 검증한 목록은 disk-chain.json에 저장했다.

호스트 관찰은 193표본, foreground 이벤트 0, queue drop 0, 최대 표본 공백
53.507ms, 100ms 초과 공백 0, 관찰 시간 약 6.195초다. 이는 이번 관찰 구간의
결과이며 호스트 입력 누출·IME·키 홀드의 검증은 아니다. 전체 격리 판정은 여전히
insufficient이며 세 앱 전체 수락 검사 또는 200개×3회 성능 비교 완료를 뜻하지 않는다.
VMware와 Hyper-V가 각각 synthetic 20/20을 통과했으며 QEMU는 helper 문제가 남아 있다.

## 2026-11-05 QEMU 대체 실행 경로 검증

기존 guest-exec helper 문제는 남아 있으나, 별도 준비 경로로 QEMU 20/20을 통과했다.
승인된 VMware 테스트 복제 VM에 TestAgent 로그인 작업을 준비하고 정상 종료 후
windows-preflight-staged.qcow2로 변환했다. 기존 QEMU 이미지는 보존했다.
작업은 QEMU 제조사·고정 UUID·새 nonce를 확인하고 게스트 내부에서만 실행한다.
QMP 이름/UUID를 확인한 뒤 QGA 파일 읽기로 결과를 회수했다. helper 다운로드나
호스트 입력 폴백은 사용하지 않았다. 이 결과가 guest-exec 복구를 의미하지는 않는다.

근거: work/bcu-comparison/qemu/preflight-050660f2ba0a48a486c41e4a5539081f.
게스트 20/20 통과, 모든 receipt의 nonce와 foreground 일치, Default input desktop,
guest UUID 1260f534-5b49-4d00-ae8a-aa12be5987ec를 확인했다.
호스트 관찰 1368표본, foreground 이벤트 0, drop 0, 최대 공백 71.462ms,
100ms 초과 공백 0, 약 43.189초다. 이 구간은 부팅·대기를 포함하므로 다른 후보의
관찰 시간과 속도 순위로 비교할 수 없다. 결과 회수 후 ACPI 종료와 프로세스 종료를 확인했다.
QEMU의 xsave state 경고는 여전히 발생하며 영향은 미측정이다.

현재 VMware·Hyper-V·QEMU 모두 synthetic 사전검사 20/20을 통과했다.
세 앱 제품 수락·200개×3회 성능 비교·IME·키 홀드·입력 누출 검증은 별도 남은 범위다.
