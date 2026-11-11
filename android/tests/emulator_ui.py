"""UI acceptance in the named, already-prepared AVD. Restore system presentation settings."""
import lab_ui as lab
from lab_ui import *

lab.P=ROOT/'work/android-lab/ui-020'
lab.P.mkdir(parents=True,exist_ok=True)
P=lab.P
results=[]
def record(name):
 results.append({'test':name,'passed':True})
 (P/'results.json').write_text(json.dumps(results,indent=2),encoding='utf8')
 print('PASS',name,flush=True)
def has(root,part):return any(part in n.get('text','') for n in root.iter('node'))
def capture(name):r=dump(name);screenshot(name);return r
def home():
 root=dump()
 if any(n.get('text')=='연결' for n in root.iter('node')):click('연결')
 else:show_app()
 time.sleep(1)
def check_home_targets(root):
 nav=next(n for n in root.iter('node') if n.get('text')=='연결' and n.get('class')=='android.widget.Button')
 nav_y=int(re.findall(r'\d+',nav.get('bounds'))[1])
 density=int(re.findall(r'\d+',adb('shell','wm','density'))[-1])/160
 for name in ['지금 한 번 복구','자동 복구 일시정지','연결','설정','기록']:
  node=next(n for n in root.iter('node') if n.get('text')==name)
  x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds')))
  assert y2-y1>=48*density,(name,node.get('bounds'))
  if name in ['지금 한 번 복구','자동 복구 일시정지']:assert y2<=nav_y

validate_target()
saved={'night':adb('shell','cmd','uimode','night').split(':')[-1].strip(),
       'font':adb('shell','settings','get','system','font_scale'),
       'rotation_auto':adb('shell','settings','get','system','accelerometer_rotation'),
       'rotation':adb('shell','settings','get','system','user_rotation')}
(P/'original-settings.json').write_text(json.dumps(saved,indent=2))
assert 'android.permission.WRITE_SECURE_SETTINGS: granted=true' in adb('shell','dumpsys','package',PKG)
assert 'android.permission.ACCESS_BACKGROUND_LOCATION: granted=true' in adb('shell','dumpsys','package',PKG)
try:
 show_app();home();resume();home()
 r=capture('home-light');check_home_targets(r);record('home actions fit without scrolling; targets at least 48dp')
 click('자동 복구 일시정지');time.sleep(2);assert not foreground()
 adb('shell','settings','put','global','adb_wifi_enabled','0')
 click('지금 한 번 복구');wait_on();record('pause and single recovery work from home')
 capture('home-paused');resume();home()
 click('설정');top();r=capture('setup-light');assert has(r,'처음 한 번 설정') and has(r,'준비가 끝났어요')
 click('PC 설정 방법',True)
 for _ in range(4):
  r=dump()
  if has(r,'주소나 ADB 명령을 입력할 필요가 없습니다'):break
  area=next(n for n in r.iter('node') if n.get('class')=='android.widget.ScrollView');x1,y1,x2,y2=map(int,re.findall(r'\d+',area.get('bounds')));adb('shell','input','swipe',str((x1+x2)//2),str(y1+(y2-y1)*4//5),str((x1+x2)//2),str(y1+(y2-y1)//3),'300')
 r=capture('pc-help')
 assert has(r,'Blink Link 설정') and not has(r,'권한 명령 복사');record('setup progress and GUI-first PC preparation instructions')
 time.sleep(4);home();click('기록');r=capture('history-light');assert has(r,'최근 동작') and has(r,'기록 복사')
 adb('shell','input','keyevent','4');time.sleep(1);assert has(dump(),'지금 한 번 복구');record('history navigation and system Back return home')
 adb('shell','am','force-stop',PKG);show_app();r=capture('home-stopped');assert has(r,'감시 중단') and has(r,'감시 다시 시작');assert not foreground()
 resume();record('stopped state and explicit restart retained')
 adb('shell','cmd','uimode','night','yes');time.sleep(2);home();capture('home-dark')
 click('설정');top();capture('setup-dark');home();record('dark theme renders connection and setup')
 adb('shell','settings','put','system','font_scale','1.3');time.sleep(2);home();r=capture('home-dark-large');check_home_targets(r)
 click('설정');top();capture('setup-dark-large');record('130 percent font keeps home controls reachable')
 adb('shell','settings','put','system','accelerometer_rotation','0');adb('shell','settings','put','system','user_rotation','1');time.sleep(3)
 r=capture('landscape-setup');assert has(r,'설정') and any(n.get('text')=='설정' and n.get('selected')=='true' for n in r.iter('node'))
 click('연결');click('지금 한 번 복구',True);capture('landscape-home');record('landscape preserves selected destination and scrollable actions')
 adb('shell','settings','put','system','user_rotation','0');adb('shell','settings','put','system','font_scale','1.0');adb('shell','cmd','uimode','night','no');time.sleep(2)
 adb('shell','pm','revoke',PKG,'android.permission.ACCESS_BACKGROUND_LOCATION');show_app();home();r=capture('home-manual-only')
 assert has(r,'자동 복구 설정이 필요해요') and has(r,'지금 한 번 복구')
 adb('shell','settings','put','global','adb_wifi_enabled','0');click('지금 한 번 복구');wait_on()
 record('manual recovery remains available without background location')
 adb('shell','pm','grant',PKG,'android.permission.ACCESS_BACKGROUND_LOCATION')
 adb('shell','pm','revoke',PKG,'android.permission.WRITE_SECURE_SETTINGS');show_app();r=capture('home-permission-needed')
 assert has(r,'처음 설정이 필요해요') and has(r,'설정 이어하기')
 click('설정 이어하기');r=capture('setup-permission-needed');assert has(r,'2단계 준비됨');record('missing permission routes to setup with accurate progress')
finally:
 adb('shell','pm','grant',PKG,'android.permission.ACCESS_BACKGROUND_LOCATION')
 adb('shell','pm','grant',PKG,'android.permission.WRITE_SECURE_SETTINGS')
 adb('shell','cmd','uimode','night',saved['night'])
 for key,value in [('font_scale',saved['font']),('user_rotation',saved['rotation']),('accelerometer_rotation',saved['rotation_auto'])]:
  if value=='null':adb('shell','settings','delete','system',key)
  else:adb('shell','settings','put','system',key,value)
show_app();home();resume();home();capture('final-home')
(P/'crash-log.txt').write_text(adb('logcat','-d','-b','crash'),encoding='utf8')
