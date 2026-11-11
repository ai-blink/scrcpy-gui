"""UI acceptance on the dedicated AVD only. Leaves one clearly named manual test fixture."""
import lab_ui as l
from lab_ui import *
l.P=ROOT/'work/android-lab/review-031';l.P.mkdir(exist_ok=True);P=l.P
name='UI check '+str(int(time.time()))
results=[]
def record(s):
 results.append(s);(P/'ui-results.json').write_text(json.dumps(results,indent=2),encoding='utf8');print('PASS',s,flush=True)
def has(r,s):return any(s in n.get('text','') for n in r.iter('node'))
def has_button(r,s):return any(n.get('text')==s and n.get('class')=='android.widget.Button' for n in r.iter('node'))
def field(desc,value):
 r=dump();n=next(n for n in r.iter('node') if n.get('content-desc')==desc);x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));adb('shell','input','keyevent','KEYCODE_MOVE_END');adb('shell','input','keyevent','--longpress','KEYCODE_DEL');adb('shell','input','text',value.replace(' ','%s'));adb('shell','input','keyevent','4')
def spinner(option):
 r=dump();n=next(n for n in r.iter('node') if n.get('class')=='android.widget.Spinner');x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));click(option)
def reopen():
 show_app();click('내 매크로 열기',True)
def list_texts():
 # A fresh list starts at its top. Traverse to the actual bottom, including off-screen rows.
 seen=set();previous=None
 for _ in range(220):
  r=dump();nodes=[n for n in r.iter('node')];seen.update(n.get('text','') for n in nodes)
  signature=tuple((n.get('text'),n.get('bounds')) for n in nodes if n.get('text'))
  if signature==previous:return seen
  previous=signature
  area=next(n for n in nodes if n.get('class')=='android.widget.ScrollView');x1,y1,x2,y2=map(int,re.findall(r'\d+',area.get('bounds')));x=(x1+x2)//2
  adb('shell','input','swipe',str(x),str(y1+(y2-y1)*4//5),str(x),str(y1+(y2-y1)//5),'250')
 raise AssertionError('List did not reach a stable bottom')
validate_target();saved={'night':adb('shell','cmd','uimode','night').split(':')[-1].strip(),'font':adb('shell','settings','get','system','font_scale')}
try:
 reopen();top();r=dump();
 if has_button(r,'조건 감시 중지'):click('조건 감시 중지');time.sleep(2.5)
 click('조건 감시 시작');time.sleep(2.5);assert has_button(dump(),'조건 감시 중지');click('조건 감시 중지');time.sleep(2.5);assert has_button(dump(),'조건 감시 시작');record('monitor button follows actual start and stop state')
 click('새 매크로 만들기');field('매크로 이름',name);spinner('충전 시작');r=dump('editor-conditions');assert not has(r,'지정 시각 (HH:mm)');screenshot('editor-conditions')
 click('동작 추가',True);field('내용 / 값','Hello from Blink');click('추가 / 적용');click('동작 추가',True);spinner('기다리기 (초)');field('내용 / 값','0');click('추가 / 적용');click('매크로 저장',True);record('editor saves charging trigger and two ordered actions')
 click('실행 · '+name,True);time.sleep(1);click('매크로 실행 기록',True);r=dump('execution-log');assert has(r,name+' · 완료');screenshot('execution-log');click('확인');record('manual sequence completes and appears in execution history')
 top();click('복제 · '+name,True);click('편집 · '+name+' 복사',True);r=dump('duplicate-editor');assert has(r,name+' 복사');assert not any(n.get('text')=='저장 후 자동 실행 허용' and n.get('checked')=='true' for n in r.iter('node'));record('duplicate opens with automation disabled')
 click('2번 동작 수정',True);spinner('기다리기 (초)');field('내용 / 값','1');click('추가 / 적용');# Find the enabled upward control for the second action.
 r=dump();n=next(n for n in r.iter('node') if n.get('text')=='위로' and n.get('enabled')=='true');x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));r=dump('reordered');assert has(r,'1. 기다리기');screenshot('editor-sequence');click('매크로 저장',True);top();click('편집 · '+name+' 복사',True);click('1번 동작 수정',True);r=dump('saved-reordered-action');assert has(r,'기다리기 (초)') and any(n.get('content-desc')=='내용 / 값' and n.get('text')=='1' for n in r.iter('node'));click('취소');click('목록으로 돌아가기');click('목록으로');record('action editing and reordering retained after saving and reopening')
 top();click('편집 · '+name+' 복사',True);click('이 매크로 삭제',True);click('삭제');adb('shell','am','force-stop',PKG);reopen();assert '편집 · '+name+' 복사' not in list_texts();record('explicit delete confirmation removes duplicate after process restart')
 adb('shell','am','force-stop',PKG);reopen();click('편집 · '+name,True);r=dump('persisted-editor');assert has(r,name);click('목록으로 돌아가기');click('목록으로');record('saved macro survives process restart');top();click('새 매크로 만들기');click('동작 추가',True);spinner('텍스트 읽기');field('내용 / 값','Draft survives recreation');adb('shell','cmd','uimode','night','yes' if saved['night']=='no' else 'no');time.sleep(2);r=dump('restored-action-draft');assert has(r,'동작 설정') and has(r,'텍스트 읽기') and any(n.get('content-desc')=='내용 / 값' and n.get('text')=='Draft survives recreation' for n in r.iter('node'));screenshot('restored-action-draft');click('취소');click('목록으로 돌아가기');click('목록으로');adb('shell','cmd','uimode','night',saved['night']);time.sleep(2);record('unapplied action draft survives activity recreation')
 adb('shell','cmd','uimode','night','yes');adb('shell','settings','put','system','font_scale','1.3');time.sleep(2);top();screenshot('macros-dark-large');click('새 매크로 만들기');screenshot('editor-dark-large');click('목록으로 돌아가기');click('목록으로');record('dark theme and 130 percent text remain operable')
finally:
 adb('shell','cmd','uimode','night',saved['night']);adb('shell','settings','put','system','font_scale',saved['font'])
time.sleep(2);top();dump('macros-final');screenshot('macros-final')
(P/'crash-log.txt').write_text(adb('logcat','-d','-b','crash'),encoding='utf8')
