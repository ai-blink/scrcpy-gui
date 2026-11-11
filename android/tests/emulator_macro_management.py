"""Persisted reorder/delete regression for the typed editor, dedicated AVD only."""
from lab_ui import *
import lab_ui as l
import base64
l.P=ROOT/'work/android-lab/macro-ux040';P=l.P
results=[]
def defs():
 out=adb('shell','am','instrument','-w','kr.blinklabs.blinklink.tests/kr.blinklabs.blinklink.tests.MacroUxReadout');return json.loads(base64.b64decode(re.search(r'BLINK_DEFS=([A-Za-z0-9+/=]+)',out).group(1)))['macros']
def reopen():
 show_app();r=dump()
 if any(n.get('text')=='내 매크로 열기' for n in r.iter('node')):click('내 매크로 열기',True)
def record(s):results.append(s);(P/'management-results.json').write_text(json.dumps(results,indent=2),encoding='utf8');print('PASS',s,flush=True)
before=defs();source=next(m for m in before if m['name']=='수동 실행 매크로' and len(m['actions'])==7);reopen();click('복제 · '+source['name'],True);new=[m for m in defs() if m['id'] not in {a['id'] for a in before}];assert len(new)==1;clone=new[0];assert not clone['enabled'];reopen();click('편집 · '+clone['name'],True)
r=dump();node=next(n for n in r.iter('node') if n.get('content-desc')=='매크로 이름 (비우면 자동)');x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));adb('shell','input','keyevent','KEYCODE_MOVE_END');adb('shell','input','keyevent',*(['KEYCODE_DEL']*len(node.get('text'))));name='UX check '+str(int(time.time()));adb('shell','input','text',name.replace(' ','%s'));adb('shell','input','keyevent','4')
click('1번 동작 수정',True);click('취소');r=dump();node=next(n for n in r.iter('node') if n.get('text')=='아래로' and n.get('enabled')=='true');x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));click('매크로 저장');stored=next(m for m in defs() if m['id']==clone['id']);assert [s['type'] for s in stored['actions']][:2]==[1,0] and stored['name']==name;record('typed actions reordered and persisted after process restart')
reopen();click('편집 · '+name,True);click('이 매크로 삭제',True);click('삭제');assert clone['id'] not in {m['id'] for m in defs()};record('cloned macro deletion verified in persisted definitions')
