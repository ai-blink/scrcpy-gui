import json,pathlib,html
root=pathlib.Path(__file__).resolve().parents[3]
lab=root/'work/bcu-app-performance'
r=json.loads((lab/'comparison.json').read_text(encoding='utf-8'))
a=json.loads((lab/'alternatives.json').read_text(encoding='utf-8'))
plan=json.loads((lab/'plan.json').read_text(encoding='utf-8-sig'))
cli=json.loads((lab/'core-cli-summary.json').read_text(encoding='utf-8-sig'))
def esc(x):return html.escape(str(x))
rows=[];detail=[]
for platform,p in r['platforms'].items():
 rows.append('<tr>'+''.join(f'<td>{esc(v)}</td>' for v in [platform,p.get('state'),p.get('qualityPassed','미측정'),round(p.get('medianWorkflowTotalSeconds',0),3) if p.get('medianWorkflowTotalSeconds') else '—',round(p.get('medianAppCpuTotalSeconds',0),3) if p.get('medianAppCpuTotalSeconds') else '—'])+'</tr>')
 for name,m in p.get('apps',{}).items():
  vals=[platform,name,round(m['startupWindowMs']['median'],1),round(m['workflowMs']['median']/1000,3),round(m['cpuSeconds']['median'],3),round(m['peakWorkingSetBytes']['median']/1048576,1)]
  detail.append('<tr>'+''.join(f'<td>{esc(v)}</td>' for v in vals)+'</tr>')
alternatives=[]
for item in a['routes']:
 links=item.get('sources',[])+([item['source']] if item.get('source') else [])
 alternatives.append('<tr>'+''.join(f'<td>{esc(item.get(k,""))}</td>' for k in ['name','status','coverage'])+'<td>'+', '.join(f'<a href="{esc(u)}">공식 근거</a>' for u in links)+'</td></tr>')
body=f'''<!doctype html><html lang="ko"><meta charset="utf-8"><title>실제 앱 격리 성능 비교</title>
<style>body{{font:16px/1.6 system-ui;max-width:1200px;margin:40px auto;padding:0 24px;color:#17202a}}table{{border-collapse:collapse;width:100%;margin:20px 0}}td,th{{border:1px solid #d8dfe5;padding:10px;text-align:left}}th{{background:#eef4fa}}code{{background:#f2f3f5}}small{{color:#52606d}}a{{color:#125bb5}}</style>
<h1>실제 앱 격리 성능 비교 · 2026-11-05</h1><p>scrcpy-gui · key-demo-osk · new-alt / Windows / 4 vCPU · 8 GiB RAM / {esc(plan['resolution'])} · 100% 배율 / 동일 공통 이미지와 앱 바이너리</p>
<p>예열 1회 제외 후 3회 측정. CPU 초는 앱 프로세스가 실제 소비한 CPU 시간이며, 벽시계 시간과 다릅니다. 기능 검사는 회차당 10개입니다.</p>
<p><strong>선택: 현재 호스트에서는 Hyper-V 헤드리스 VM.</strong> 이번 세 앱 작업 시간과 앱 CPU 시간 중앙값이 가장 낮고 기능 검사는 세 환경 모두 30/30 통과했습니다. 메모리 차이는 작습니다. 최신 소스를 새로 빌드한 비교가 아니라 동일한 기존 앱 스냅샷의 비교입니다.</p>
<table><tr><th>환경</th><th>상태</th><th>통과 / 30</th><th>세 앱 작업 시간 합계 중앙값(초)</th><th>앱 CPU 합계 중앙값(초)</th></tr>{''.join(rows)}</table>
<h2>앱별 결과</h2><table><tr><th>환경</th><th>앱</th><th>시작 관측(ms)</th><th>작업(초)</th><th>CPU(초)</th><th>최대 상주 메모리 중앙값(MiB)</th></tr>{''.join(detail)}</table>
<h2>해석 범위</h2><ul>{''.join('<li>'+esc(x)+'</li>' for x in r['limitations'])}</ul>
<p>1920×1080 예비 검증에서는 VMware와 Hyper-V가 통과했으나, 현재 QEMU 구성은 요청한 화면 크기를 만들지 못했습니다. DPI 인식 설정 및 VGA 기본 해상도 변경만으로 해결되지 않았습니다. QEMU에서 별도로 관측한 VMware Tools 오류 팝업은 본 측정에서 불필요한 VMware 도구를 중단해 제거했습니다. 이는 QEMU 자체의 모든 고해상도 구성에 대한 불가능 판정이 아닙니다.</p>
<p>호스트는 Hyper-V가 활성화된 상태입니다. VMware 로그에서 ULM/WHP 사용을 확인했습니다. Hyper-V를 끄고 재부팅한 VMware 네이티브 모드는 이 결과에 포함하지 않습니다. VM 전체 메모리·CPU는 플랫폼별 회계 방식이 달라 vmwp의 작은 WorkingSet을 Hyper-V 전체 RAM으로 해석하면 안 됩니다.</p>
<h2>헤드리스·CLI 대안</h2><table><tr><th>방식</th><th>검증 상태</th><th>적용 범위</th><th>근거</th></tr>{''.join(alternatives)}</table>
<p>new-alt Core의 네이티브 dotnet vstest는 게스트 세션 0에서 화면 없이 실행했습니다. 결과: {esc([(x['passed'], x['total'], round(x['seconds'],3)) for x in cli['rounds']])} (통과, 전체, 초). 540개씩 3회 모두 통과했습니다. 이는 백엔드 회귀 검사이며 GUI 작업과 범위가 달라 두 실행 시간으로 속도 배수를 계산할 수 없습니다. CLI-Anything 구현의 측정 결과도 아닙니다. <a href="core-cli-summary.json">CLI 실행 근거</a></p>
<p>CLI-Anything의 레포·등록 목록 검토 revision: <code>{esc(json.loads((lab/'cli-anything-inventory.json').read_text())['sha'])}</code>. 지원 어댑터가 없는 세 앱의 성능 수치를 추정하지 않았습니다.</p>
<p>{esc(a.get('inputAppInference',''))}</p>
<p><a href="comparison.json">집계 JSON</a> · <a href="plan.json">실행 조건</a> · <a href="alternatives.json">대안 검토</a></p></html>'''
(lab/'report.html').write_text(body,encoding='utf-8')
print(lab/'report.html')
