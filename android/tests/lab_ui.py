# Guest-only Android UI test helpers. Main setup requires a fresh app install.
import subprocess,time,pathlib,xml.etree.ElementTree as E,re,json
ROOT=pathlib.Path(__file__).resolve().parents[2]
P=ROOT / 'work' / 'android-lab' / 'review-fix'
P.mkdir(parents=True,exist_ok=True)
ADB=r'C:\app\scrcpy-win64-v4.1\adb.exe'
SER='emulator-5580'; PKG='kr.blinklabs.blinklink'
AVD='BlinkLink16'
def raw(*args):
 r=subprocess.run([ADB,'-s',SER,*args],capture_output=True,timeout=40)
 if r.returncode:raise RuntimeError(r.stderr.decode(errors='replace'))
 return r.stdout.decode('utf8',errors='replace').strip()
def validate_target(require_package=True):
 if not SER.startswith('emulator-'):raise RuntimeError('Only an Android emulator is permitted')
 name=raw('emu','avd','name').splitlines()[0].strip()
 if name!=AVD:raise RuntimeError('Wrong AVD: '+name)
 if raw('shell','getprop','ro.kernel.qemu')!='1':raise RuntimeError('Not an emulator')
 if require_package and not raw('shell','pm','path',PKG).startswith('package:'):raise RuntimeError('App is not installed')
def adb(*args):
 validate_target()
 return raw(*args)
def dump(name='current'):
 adb('shell','uiautomator','dump','/sdcard/blink.xml');xml=adb('shell','cat','/sdcard/blink.xml');(P/(name+'.xml')).write_text(xml,encoding='utf8');return E.fromstring(xml)
def screenshot(name):
 validate_target()
 (P/(name+'.png')).write_bytes(subprocess.check_output([ADB,'-s',SER,'exec-out','screencap','-p']))
def wait_on(limit=45):
 start=time.monotonic()
 while time.monotonic()-start<limit:
  if adb('shell','settings','get','global','adb_wifi_enabled')=='1':return round(time.monotonic()-start,1)
  time.sleep(1)
 raise AssertionError('Enable timed out')
def assert_off_for(seconds):
 deadline=time.monotonic()+seconds
 while time.monotonic()<deadline:
  assert adb('shell','settings','get','global','adb_wifi_enabled')=='0', 'Unexpected enable'
  time.sleep(2)
def foreground():
 return 'isForeground=true' in adb('shell','dumpsys','activity','services',PKG)
def show_app():
 adb('shell','am','start','-n',PKG+'/.MainActivity');time.sleep(2)
def resume():
 show_app()
 texts=[n.get('text') for n in dump().iter('node')]
 if '자동 복구 일시정지' in texts:return
 click('감시 다시 시작' if '감시 다시 시작' in texts else '자동 복구 시작');click('시작');time.sleep(2)
 assert foreground()
def click(text,scroll=False):
 for i in range(8 if scroll else 1):
  root=dump()
  for n in root.iter('node'):
   if n.get('text')==text:
    x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')))
    if y2-y1<40:continue
    adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));time.sleep(.6);return
  if scroll:adb('shell','input','swipe','540','1950','540','650','350');time.sleep(.3)
 raise RuntimeError('Not visible: '+text)
def top():
 for _ in range(5):adb('shell','input','swipe','540','500','540','1950','200')
if __name__=='__main__':
 adb('shell','am','start','-n',PKG+'/.MainActivity')
 click('자동 복구 시작');root=dump('missing-permission');assert any(n.get('text')=='준비가 필요합니다' for n in root.iter('node'));click('확인');print('PASS missing permission gate',flush=True)
 for perm in ['ACCESS_COARSE_LOCATION','ACCESS_FINE_LOCATION','ACCESS_BACKGROUND_LOCATION','POST_NOTIFICATIONS','WRITE_SECURE_SETTINGS']:
  adb('shell','pm','grant',PKG,'android.permission.'+perm)
 adb('shell','cmd','location','set-location-enabled','true')
 click('현재 Wi-Fi 등록',True);root=dump('register');print([(n.get('text'),n.get('bounds')) for n in root.iter('node') if n.get('text')],flush=True)
 click('등록');top();adb('shell','settings','put','global','adb_wifi_enabled','0');click('자동 복구 시작');click('시작');time.sleep(3);dump('first-recovery');screenshot('first-recovery');print('ADB_WIFI_ENABLED',adb('shell','settings','get','global','adb_wifi_enabled'),flush=True)
