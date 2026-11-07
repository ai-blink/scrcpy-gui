"""Summarize measured app workflows; do not invent scores for unsupported routes."""
import json,statistics as st, pathlib,html
root=pathlib.Path(__file__).resolve().parents[3]
lab=root/'work/bcu-app-performance'
plan=json.loads((lab/'plan.json').read_text(encoding='utf-8-sig'))
prefix=plan.get('outputPrefix','')
report={'platforms':{},'limitations':[
 'Three measured warm app starts after one warm-up; not randomized boot-order or cold-cache trials.',
 'Workflow times include fixed waits and UIA probes. Startup is window availability observed at 300ms polling, not first rendered frame.',
 'App CPU is target-process CPU time, excludes child processes. Peak working set is resident memory, not allocation.',
 'Host process counters and Hyper-V partition CPU/assigned RAM have different accounting; do not rank them as equivalent.',
 'Host user workload is not suspended; host load is retained as a confounder.',
 'Quality checks cover navigation, synthetic text, command preview, window movement and OSK focus; no IME, physical device, gaming output or image-fidelity certification.',
 'CLI/backend contract tests are not interchangeable with actual GUI input acceptance.'
]}
hashes={}
for platform in ['vmware','hyperv','qemu']:
 p=lab/(prefix+platform)/'summary.json'
 if not p.exists():report['platforms'][platform]={'state':'not_collected'};continue
 s=json.loads(p.read_text(encoding='utf-8-sig'))
 rounds=[r for r in s.get('rounds',[]) if not r['warmup']]
 data={'state':s['state'],'error':s.get('error'),'rounds':len(rounds),'passed':sum(r['passed'] for r in rounds),'apps':{}}
 for name in ['scrcpy-gui','key-demo-osk','new-alt']:
  apps=[a for r in rounds for a in r['result'].get('apps',[]) if a['name']==name and 'workflowMs' in a]
  if not apps:continue
  hashes.setdefault(name,set()).update(a['sha256'] for a in apps)
  data['apps'][name]={k:{'median':st.median(a[k] for a in apps),'min':min(a[k] for a in apps),'max':max(a[k] for a in apps)} for k in ['startupWindowMs','workflowMs','cpuSeconds','peakWorkingSetBytes','privateBytes']}
 if len(rounds)==3 and all(r['passed'] for r in rounds):
  data['medianWorkflowTotalSeconds']=st.median(sum(a['workflowMs'] for a in r['result']['apps'])/1000 for r in rounds)
  data['medianAppCpuTotalSeconds']=st.median(sum(a['cpuSeconds'] for a in r['result']['apps']) for r in rounds)
  data['qualityPassed']=sum(sum(a['pass'] for a in r['result']['receipts']) for r in rounds)
  data['qualityTotal']=sum(len(r['result']['receipts']) for r in rounds)
 samples=lab/(prefix+platform)/'resources.ndjson'
 if samples.exists():
  rows=[]
  for line in samples.read_text(encoding='utf-8-sig').splitlines():
   try:rows.append(json.loads(line))
   except ValueError:pass
  load=[r['host']['PercentProcessorTime'] for r in rows if r.get('host')]
  data['hostCpuWholeRun']={'samples':len(load),'median':st.median(load) if load else None,'max':max(load) if load else None}
  data['hostProcessPeakWorkingSetBytes']=max((p['workingSetBytes'] for r in rows for p in r['processes']),default=None)
  data['hypervAssignedRamPeakBytes']=max((r.get('hypervVm',{}).get('MemoryAssigned',0) for r in rows),default=None)
 report['platforms'][platform]=data
report['matchingAppExeHashes']=all(len(v)==1 for v in hashes.values()) if hashes else None
report['appExeHashes']={k:sorted(v) for k,v in hashes.items()}
valid={k:v for k,v in report['platforms'].items() if v.get('qualityPassed')==30 and v.get('rounds')==3}
report['observedFastest']=min(valid,key=lambda k:valid[k]['medianWorkflowTotalSeconds']) if len(valid)==3 else None
report['observedLowestAppCpu']=min(valid,key=lambda k:valid[k]['medianAppCpuTotalSeconds']) if len(valid)==3 else None
(lab/'comparison.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(report,indent=2,ensure_ascii=False))
