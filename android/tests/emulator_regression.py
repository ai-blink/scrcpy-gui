# Run against the prepared dedicated emulator-5580 only.
import sys,time,json
from lab_ui import *
results=[]
def record(n,start=None):
 r={'test':n,'passed':True}
 if start:r['seconds']=round(time.monotonic()-start,1)
 results.append(r);(P/'runtime-results.json').write_text(json.dumps(results,indent=2),encoding='utf8');print(r,flush=True)
def wait_on(limit=45):
 start=time.monotonic()
 while time.monotonic()-start<limit:
  if adb('shell','settings','get','global','adb_wifi_enabled')=='1':return start
  time.sleep(1)
 raise AssertionError('Enable timed out')
wait_on();record('recovery after app update')
adb('shell','input','keyevent','3');time.sleep(6);adb('shell','settings','put','global','adb_wifi_enabled','0');start=wait_on();record('background setting-off recovery',start)
adb('shell','svc','wifi','disable');time.sleep(3);assert adb('shell','settings','get','global','adb_wifi_enabled')=='0';record('WiFi off stays off');adb('shell','svc','wifi','enable');start=wait_on();record('WiFi reconnect recovery',start)
adb('shell','am','start','-n',PKG+'/.MainActivity');dump('working');screenshot('working');click('자동 복구 일시정지');adb('shell','settings','put','global','adb_wifi_enabled','0');time.sleep(33);assert adb('shell','settings','get','global','adb_wifi_enabled')=='0';record('pause prevents recovery')
click('자동 복구 시작');click('시작');wait_on();record('resume recovery')
adb('shell','input','keyevent','3');adb('shell','cmd','location','set-location-enabled','false');time.sleep(2);adb('shell','settings','put','global','adb_wifi_enabled','0');time.sleep(33);assert adb('shell','settings','get','global','adb_wifi_enabled')=='0';record('unknown SSID fails closed');adb('shell','cmd','location','set-location-enabled','true');wait_on();record('location restoration recovers')
adb('shell','am','start','-n',PKG+'/.MainActivity');dump('runtime-final');screenshot('runtime-final')
