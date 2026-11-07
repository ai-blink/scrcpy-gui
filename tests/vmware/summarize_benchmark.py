"""Validate receipts and summarize paced guest workflow timings (not raw input latency)."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / 'work' / 'bcu-comparison'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def stats(rows):
    passed = [r for r in rows if r['status'] == 'pass' and r['foregroundMatchesFixture']]
    times = sorted(float(r['guestLocalCompletionMs']) for r in passed)
    def pct(p):
        return round(times[math.ceil(len(times) * p) - 1], 3) if times else None
    return dict(count=len(rows), passed=len(passed), p50Ms=pct(.5), p95Ms=pct(.95), p99Ms=pct(.99))


def main():
    result = {'metric': 'guest workflow completion; consult per-candidate timingDefinition and fixtureRevision',
              'design': '3 consecutive rounds of 200 actions in one interactive guest process; same fixed action order',
              'limitations': ['not raw input latency', 'not product acceptance or IME',
                              'other host workloads and VMs are not controlled', 'no hypervisor speed ranking'],
              'candidates': {}}
    for name, folder in [('vmware', ROOT/'work'/'vmware-background'), ('hyperv', LAB/'hyperv'), ('qemu', LAB/'qemu')]:
        candidates = []
        for path in folder.glob('preflight-*/**/summary.json'):
            if read(path).get('planned') == 600 and not read(path).get('legacyDrag', False):
                candidates.append(path)
        if not candidates:
            result['candidates'][name] = {'state': 'not_run'}
            continue
        path = max(candidates, key=lambda p: p.stat().st_mtime)
        summary = read(path)
        rows = [json.loads(line) for line in path.with_name('actions.ndjson').read_text(encoding='utf-8-sig').splitlines()]
        assert len(rows) == 600 and len({r['actionId'] for r in rows}) == 600
        assert all(r['runId'] == summary['runId'] for r in rows)
        assert summary['expectedUuid'].lower() == summary['actualUuid'].lower()
        assert all(sum(r['round'] == n for r in rows) == 200 for n in (1, 2, 3))
        assert summary['executed'] == 600
        if summary.get('fixtureRevision') == 'drag-input-ack-v3':
            for r in rows:
                if r['kind'] == 'drag_selection' and r['status'] == 'pass':
                    o = r['oracle']
                    assert o['leftDownMessages'] == o['leftUpMessages'] == 1
                    assert o['heldMoveMessages'] > 0 and o['doubleClickMessages'] == 0
                    assert o['selectionLength'] > 0 and o['captureReleased']
        observer = path.parent / 'host-health.json'
        if not observer.exists():
            observer = path.parent.parent / 'host-health.json'
        result['candidates'][name] = dict(state='measured', evidence=str(path.parent),
            fixtureRevision=summary.get('fixtureRevision', 'baseline-v1'),
            timingDefinition=summary.get('timingDefinition'),
            failures=[r for r in rows if r['status'] != 'pass' or not r['foregroundMatchesFixture']],
            overall=stats(rows), rounds={str(n): stats([r for r in rows if r['round'] == n]) for n in (1,2,3)},
            kinds={k: stats([r for r in rows if r['kind'] == k]) for k in sorted({r['kind'] for r in rows})},
            observer=read(observer))
    output = LAB / 'benchmark-200x3.json'
    output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    lines = ['# BCU 200 × 3 작업 완료 시간 비교', '',
             '각 후보에서 동일한 20개 작업 묶음을 10번씩, 같은 게스트 프로세스에서 3회 연속 실행한다.',
             '회차당 클릭 60, 문자 입력 40, 휠 40, 드래그 30, 캡처 30개다.',
             '측정값은 게스트 작업 완료 시간이다. v3 드래그는 수신 확인을 기다리며, 나머지는 고정 Pump 대기를 포함한다. 순수 입력 지연,',
             '전체 앱 수락 검사 또는 하이퍼바이저 속도 순위를 뜻하지 않는다. 백분위는 nearest-rank다.',
             '백분위는 성공한 동작만 집계하며 실패는 성공률과 원본 receipt에 별도 보존한다.',
             '다른 VM과 사용자 작업의 부하를 통제하지 않았으며 재부팅·회차 순서 무작위화는 하지 않았다.', '',
             '| 후보 | 회차 | 통과/전체 | p50 ms | p95 ms | p99 ms |',
             '|---|---|---:|---:|---:|---:|']
    for name, item in result['candidates'].items():
        if item['state'] != 'measured':
            lines.append(f'| {name} | 미실행 | — | — | — | — |')
            continue
        for label, values in [('전체', item['overall']), *item['rounds'].items()]:
            lines.append(f"| {name} | {label} | {values['passed']}/{values['count']} | {values['p50Ms']} | {values['p95Ms']} | {values['p99Ms']} |")
    for name, item in result['candidates'].items():
        if item['state'] != 'measured':
            continue
        h = item['observer']
        lines += ['', f'## {name}', '', f"근거: `{item['evidence']}`", '',
                  f"검사 버전: `{item['fixtureRevision']}`. v3 드래그 준비에는 OS 더블클릭 시간+50ms 대기가 추가되며 해당 대기는 동작 시간에서 제외된다. 이전 버전의 지연과 직접 비교하지 않는다.", '',
                  f"호스트 관찰: {h['samples']}표본, foreground 이벤트 {h['foregroundEvents']}건, queue drop {h['queueDrops']}건.",
                  'foreground 이벤트는 원인 미상이며 사용자 조작과 VM 간섭을 구분하지 못한다. 입력 누출·IME·키 홀드는 미측정이다.', '',
                  '| 동작 | 통과/전체 | p50 ms | p95 ms | p99 ms |', '|---|---:|---:|---:|---:|']
        for kind, v in item['kinds'].items():
            lines.append(f"| {kind} | {v['passed']}/{v['count']} | {v['p50Ms']} | {v['p95Ms']} | {v['p99Ms']} |")
        for failure in item['failures']:
            lines += ['', f"실패 {failure['actionId']} (회차 {failure['round']}, {failure['kind']}): `{json.dumps(failure['oracle'])}`. 원인 미확정."]
    lines += ['', 'QEMU는 guest-exec 대신 사전 준비한 로그인 작업으로 실행하고 QGA로 결과를 읽었다.',
              'QEMU의 xsave 경고 영향은 미측정이다. 1픽셀 색상 캡처는 전체 화면 전송 성능 측정이 아니다.',
              'double_click은 두 번의 MouseDown 수신 확인이며 일반 앱의 더블클릭 의미 검사가 아니다.', '']
    lines += ['## 드래그 실패 진단 및 수정', '',
              '수정 전 1,800개 결과는 BCU-BENCHMARK-200X3-BASELINE.md와 원본 receipt에 보존했다.',
              'Hyper-V 진단 실행 b6e28882558d4760bb57dd4a778c4a81에서 기존 방식은 598/600이었다.',
              '재현 실패 2건은 누름·해제 메시지가 각각 1개였지만 누른 상태 이동 메시지는 0개였다.',
              '별도로 드래그 30건이 WM_LBUTTONDBLCLK로 처리돼 문자열 전체 36자를 선택했다.',
              '즉 기존 Cursor.Position 변경과 고정 대기만으로는 유효한 독립 드래그 수신을 보장하지 못했다.',
              '원래 6건에는 상세 메시지 계측이 없으므로 각각의 내부 OS 원인을 소급 확정하지는 않는다.', '',
              '간격만 분리한 중간 실험 15bc506b2d8946dea3764323a33aafe6은 600/600으로 개선됐다.',
              '최종 v3는 OS 더블클릭 시간+50ms로 독립 동작을 분리하고, 이동을 SendInput으로 주입하며',
              '이동 메시지 병합을 끈다. 누름·캡처, 누른 상태 이동·선택, 해제·캡처 반환을 단계별로 확인한다.',
              '각 확인은 2초 제한이며 실패를 숨기는 재시도나 선택값의 강제 대입은 없다.',
              '검사 드라이버를 수정했으며 scrcpy-gui, key-demo-osk, new-alt의 제품 코드는 이 수정 대상이 아니다.', '',
              'API 근거: [마우스 메시지 병합 제어](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-mouseinput),',
              '[Windows 더블클릭 판정](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-lbuttondblclk).', '']
    (ROOT / 'notes' / 'BCU-BENCHMARK-200X3.md').write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
