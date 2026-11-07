# BCU 200 × 3 작업 완료 시간 비교

각 후보에서 동일한 20개 작업 묶음을 10번씩, 같은 게스트 프로세스에서 3회 연속 실행한다.
회차당 클릭 60, 문자 입력 40, 휠 40, 드래그 30, 캡처 30개다.
측정값은 고정 30ms Pump 대기를 포함하는 게스트 작업 완료 시간이다. 순수 입력 지연,
전체 앱 수락 검사 또는 하이퍼바이저 속도 순위를 뜻하지 않는다. 백분위는 nearest-rank다.
백분위는 성공한 동작만 집계하며 실패는 성공률과 원본 receipt에 별도 보존한다.
다른 VM과 사용자 작업의 부하를 통제하지 않았으며 재부팅·회차 순서 무작위화는 하지 않았다.

| 후보 | 회차 | 통과/전체 | p50 ms | p95 ms | p99 ms |
|---|---|---:|---:|---:|---:|
| vmware | 전체 | 600/600 | 49.575 | 142.625 | 146.006 |
| vmware | 1 | 200/200 | 49.271 | 143.851 | 147.331 |
| vmware | 2 | 200/200 | 49.926 | 142.625 | 145.912 |
| vmware | 3 | 200/200 | 48.86 | 140.822 | 144.839 |
| hyperv | 전체 | 598/600 | 47.305 | 127.134 | 142.976 |
| hyperv | 1 | 198/200 | 47.305 | 127.416 | 142.976 |
| hyperv | 2 | 200/200 | 34.945 | 126.695 | 142.906 |
| hyperv | 3 | 200/200 | 47.621 | 127.134 | 142.383 |
| qemu | 전체 | 596/600 | 47.596 | 111.219 | 126.039 |
| qemu | 1 | 199/200 | 48.298 | 111.759 | 126.844 |
| qemu | 2 | 199/200 | 34.422 | 110.668 | 112.355 |
| qemu | 3 | 198/200 | 35.702 | 111.094 | 112.447 |

## vmware

근거: `C:\ai\projects\scrcpy-gui\work\vmware-background\preflight-f1e3d91bf1d248f2936fdec3ca4b0491`

호스트 관찰: 2099표본, foreground 이벤트 2건, queue drop 0건.
foreground 이벤트는 원인 미상이며 사용자 조작과 VM 간섭을 구분하지 못한다. 입력 누출·IME·키 홀드는 미측정이다.

| 동작 | 통과/전체 | p50 ms | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| double_click | 30/30 | 67.122 | 83.208 | 96.827 |
| drag_selection | 90/90 | 112.561 | 145.299 | 161.318 |
| frame_marker | 90/90 | 19.136 | 32.778 | 37.22 |
| left_click | 120/120 | 34.41 | 51.073 | 66.141 |
| right_click | 30/30 | 32.228 | 46.105 | 62.795 |
| unicode_diagnostic_not_ime | 120/120 | 51.368 | 66.684 | 67.712 |
| wheel | 120/120 | 49.677 | 145.477 | 146.511 |

## hyperv

근거: `C:\ai\projects\scrcpy-gui\work\bcu-comparison\hyperv\preflight-d7669afe5edf48119386de6d8ce3a3fe`

호스트 관찰: 1756표본, foreground 이벤트 5건, queue drop 0건.
foreground 이벤트는 원인 미상이며 사용자 조작과 VM 간섭을 구분하지 못한다. 입력 누출·IME·키 홀드는 미측정이다.

| 동작 | 통과/전체 | p50 ms | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| double_click | 30/30 | 64.745 | 81.061 | 81.528 |
| drag_selection | 88/90 | 110.616 | 127.416 | 141.772 |
| frame_marker | 90/90 | 17.056 | 18.002 | 33.393 |
| left_click | 120/120 | 33.253 | 34.829 | 49.763 |
| right_click | 30/30 | 31.57 | 32.092 | 32.115 |
| unicode_diagnostic_not_ime | 120/120 | 48.317 | 49.213 | 64.61 |
| wheel | 120/120 | 47.953 | 142.834 | 143.5 |

실패 action-0017 (회차 1, drag_selection): `{"captureReleased": true, "selectionLength": 0}`. 원인 미확정.

실패 action-0177 (회차 1, drag_selection): `{"captureReleased": true, "selectionLength": 0}`. 원인 미확정.

## qemu

근거: `C:\ai\projects\scrcpy-gui\work\bcu-comparison\qemu\preflight-fe0339a1276c4b2aa3ec3c1f513450d2\guest`

호스트 관찰: 3093표본, foreground 이벤트 3건, queue drop 0건.
foreground 이벤트는 원인 미상이며 사용자 조작과 VM 간섭을 구분하지 못한다. 입력 누출·IME·키 홀드는 미측정이다.

| 동작 | 통과/전체 | p50 ms | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| double_click | 30/30 | 64.733 | 80.086 | 81.612 |
| drag_selection | 86/90 | 95.263 | 124.498 | 126.834 |
| frame_marker | 90/90 | 17.577 | 18.571 | 37.212 |
| left_click | 120/120 | 33.065 | 49.016 | 51.403 |
| right_click | 30/30 | 31.922 | 48.029 | 48.175 |
| unicode_diagnostic_not_ime | 120/120 | 48.975 | 64.988 | 66.257 |
| wheel | 120/120 | 48.009 | 110.816 | 126.844 |

실패 action-0017 (회차 1, drag_selection): `{"captureReleased": true, "selectionLength": 0}`. 원인 미확정.

실패 action-0297 (회차 2, drag_selection): `{"captureReleased": true, "selectionLength": 0}`. 원인 미확정.

실패 action-0497 (회차 3, drag_selection): `{"captureReleased": true, "selectionLength": 0}`. 원인 미확정.

실패 action-0577 (회차 3, drag_selection): `{"captureReleased": true, "selectionLength": 0}`. 원인 미확정.

QEMU는 guest-exec 대신 사전 준비한 로그인 작업으로 실행하고 QGA로 결과를 읽었다.
QEMU의 xsave 경고 영향은 미측정이다. 1픽셀 색상 캡처는 전체 화면 전송 성능 측정이 아니다.
double_click은 두 번의 MouseDown 수신 확인이며 일반 앱의 더블클릭 의미 검사가 아니다.
