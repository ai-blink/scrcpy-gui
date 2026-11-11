"""UX acceptance for every currently supported trigger/action on the named AVD."""
import lab_ui as l
from lab_ui import *
l.P=ROOT/'work/android-lab/macro-ux040';l.P.mkdir(exist_ok=True);P=l.P
checks=[]
def record(s):checks.append(s);(P/'results.json').write_text(json.dumps(checks,indent=2),encoding='utf8');print('PASS',s,flush=True)
def has(r,text):return any(text in n.get('text','') for n in r.iter('node'))
def defs():
 out=adb('shell','am','instrument','-w','kr.blinklabs.blinklink.tests/kr.blinklabs.blinklink.tests.MacroUxReadout');import base64
 return json.loads(base64.b64decode(re.search(r'BLINK_DEFS=([A-Za-z0-9+/=]+)',out).group(1)))['macros']

def spinner(option):
 r=dump();n=next(n for n in r.iter('node') if n.get('class')=='android.widget.Spinner');x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));click(option)
def add(kind):click('동작 추가',True);spinner(kind)
def field_value(r,label):return next(n.get('text') for n in r.iter('node') if n.get('content-desc')==label)
validate_target();saved={'night':adb('shell','cmd','uimode','night').split(':')[-1].strip(),'font':adb('shell','settings','get','system','font_scale')}
try:
 before={m['id'] for m in defs()};show_app();click('내 매크로 열기',True);click('새 매크로 만들기')
 for label in ['수동 실행','매일 지정 시각','충전 시작','충전 종료','Wi-Fi 연결','화면 켜짐','잠금 해제']:spinner(label)
 spinner('매일 지정 시각');click('매일 09:00에 실행');r=dump('time-picker');assert any(n.get('class')=='android.widget.TimePicker' for n in r.iter('node'));screenshot('time-picker');click('확인' if has(r,'확인') else 'OK');record('all seven triggers selectable; daily time uses native picker')
 click('Wi-Fi 제한 없음 · 선택하기',True);r=dump('wifi-picker');assert has(r,'제한 없이 실행');options=[n.get('text') for n in r.iter('node') if ' · 현재 연결됨' in n.get('text','')];assert options,'prepared AVD needs visible current SSID';click(options[0]);record('Wi-Fi selected from current connection without typing SSID')
 spinner('수동 실행') if any(n.get('class')=='android.widget.Spinner' for n in dump().iter('node')) else None
 # Return to the top to pick the trigger if scrolled.
 top();spinner('수동 실행')
 add('알림 표시');click('충전이 시작됐어요.');click('동작 저장');record('notification uses plain language and one-tap example')
 add('텍스트 읽기');click('일정을 확인할 시간입니다.');adb('shell','cmd','uimode','night','yes' if saved['night']=='no' else 'no');time.sleep(2);r=dump('speech-draft');assert field_value(r,'읽어줄 문장')=='일정을 확인할 시간입니다.';screenshot('speech-draft');click('동작 저장');record('speech draft and selected type survive theme recreation')
 add('기다리기 (초)');click('5초',True);r=dump('wait-picker');assert has(r,'5초 기다리기');assert not any(n.get('class')=='android.widget.EditText' for n in r.iter('node'));screenshot('wait-picker');click('동작 저장');record('wait chosen by seconds preset, no generic value field')
 add('앱 열기');click('앱을 선택하세요');time.sleep(2);r=dump('apps-picker');area=next(n for n in r.iter('node') if n.get('class')=='android.widget.ListView');items=[n for n in area.iter('node') if n.get('text')];assert items;choice=next((n.get('text') for n in items if n.get('text') in ['Settings','설정']),items[0].get('text'));click(choice);r=dump('app-chosen');assert not has(r,'패키지 이름');screenshot('app-chosen');click('동작 저장');record('installed app selected by name without package input')
 add('미디어 음량');click('작게 · 25%',True);r=dump('volume-picker');assert has(r,'미디어 음량 25%');screenshot('volume-picker');click('동작 저장');record('volume selected by labeled percent preset')
 add('진동');click('짧게 · 0.2초',True);r=dump('vibration-picker');assert has(r,'0.20초 진동');screenshot('vibration-picker');click('동작 저장');record('vibration selected in seconds without millisecond conversion')
 add('무선 디버깅 복구');r=dump('recovery-picker');assert has(r,'입력할 값이 없어요');assert not any(n.get('class')=='android.widget.EditText' for n in r.iter('node'));click('동작 저장');record('recovery action has no technical value input')
 r=dump();save=next(n for n in r.iter('node') if n.get('text')=='매크로 저장');bounds=list(map(int,re.findall(r'\d+',save.get('bounds'))));assert bounds[3]>bounds[1] and bounds[1]>0;click('매크로 저장');new=[m for m in defs() if m['id'] not in before];assert len(new)==1;macro=new[0];assert macro['name']=='수동 실행 매크로' and not macro['enabled'];a=macro['actions'];assert [x['type'] for x in a]==list(range(7));assert a[0]['value']=='충전이 시작됐어요.' and a[1]['value']=='일정을 확인할 시간입니다.' and a[2]['value']=='5' and '.' in a[3]['value'] and a[4]['value']=='25' and a[5]['value']=='200' and a[6]['value']=='';record('all seven typed actions persisted correctly with auto name and fixed save')
 show_app();click('내 매크로 열기',True);top();click('예제에서 시작하기');click('충전이 시작되면 알림');r=dump('template-editor');assert has(r,'충전 시작 알림');screenshot('template-editor');click('매크로 저장');record('ready-to-edit template saves without technical configuration')
finally:
 adb('shell','cmd','uimode','night',saved['night']);adb('shell','settings','put','system','font_scale',saved['font'])
(P/'crash-log.txt').write_text(adb('logcat','-d','-b','crash'),encoding='utf8')
