# Guest-only Android UI test helpers. Main setup requires a fresh app install.
import subprocess,time,pathlib,xml.etree.ElementTree as E,re,json
P=pathlib.Path(__file__).resolve().parents[2] / 'work' / 'android-lab'
P.mkdir(parents=True,exist_ok=True)
ADB=r'C:\app\scrcpy-win64-v4.1\adb.exe'
SER='emulator-5580'; PKG='kr.blinklabs.blinklink'
def adb(*args):
 if not SER.startswith('emulator-'):raise RuntimeError('Only an Android emulator is permitted')
 r=subprocess.run([ADB,'-s',SER,*args],capture_output=True,timeout=40)
 if r.returncode:raise RuntimeError(r.stderr.decode(errors='replace'))
 return r.stdout.decode('utf8',errors='replace').strip()
def dump(name='current'):
 adb('shell','uiautomator','dump','/sdcard/blink.xml');xml=adb('shell','cat','/sdcard/blink.xml');(P/(name+'.xml')).write_text(xml,encoding='utf8');return E.fromstring(xml)
def screenshot(name): (P/(name+'.png')).write_bytes(subprocess.check_output([ADB,'-s',SER,'exec-out','screencap','-p']))
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
