"""Focused native time-state and app-name search acceptance, dedicated AVD only."""
from lab_ui import *
import lab_ui as l
l.P=ROOT/'work/android-lab/macro-ux040';P=l.P
saved=adb('shell','cmd','uimode','night').split(':')[-1].strip()
def spinner(text):
 r=dump();n=next(n for n in r.iter('node') if n.get('class')=='android.widget.Spinner');x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));click(text)
try:
 show_app();r=dump();
 if any(n.get('text')=='내 매크로 열기' for n in r.iter('node')):click('내 매크로 열기',True)
 click('새 매크로 만들기');spinner('매일 지정 시각');click('매일 09:00에 실행');adb('shell','cmd','uimode','night','yes' if saved=='no' else 'no');time.sleep(2);r=dump('time-draft-restored');assert any(n.get('class')=='android.widget.TimePicker' for n in r.iter('node'));screenshot('time-draft-restored');click('확인' if any(n.get('text')=='확인' for n in r.iter('node')) else 'OK');print('PASS native time picker survives activity recreation',flush=True)
 click('동작 추가',True);spinner('앱 열기');click('앱을 선택하세요');time.sleep(2);r=dump();n=next(n for n in r.iter('node') if n.get('content-desc')=='앱 이름 검색');x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));adb('shell','input','text','Blink');adb('shell','input','keyevent','4');r=dump('app-name-search');listview=next(n for n in r.iter('node') if n.get('class')=='android.widget.ListView');texts=[n.get('text') for n in listview.iter('node') if n.get('text')];assert texts==['Blink Link'],texts;screenshot('app-name-search');click('Blink Link');click('취소');click('목록으로 돌아가기');click('목록으로');print('PASS installed apps filtered by human app name',flush=True)
 (P/'focused-results.json').write_text(json.dumps({'time_state':True,'app_name_search':True}),encoding='utf8')
finally:adb('shell','cmd','uimode','night',saved)
