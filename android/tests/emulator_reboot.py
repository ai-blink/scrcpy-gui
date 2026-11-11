# Run against the prepared dedicated emulator-5580 only.
import sys,time,json,subprocess
from lab_ui import *
adb('shell','am','start','-n',PKG+'/.MainActivity');time.sleep(2)
print('before reboot:',adb('shell','settings','get','global','adb_wifi_enabled'),flush=True)
(P/'before-reboot-services.txt').write_text(adb('shell','dumpsys','activity','services',PKG),encoding='utf8')
adb('reboot');start=time.monotonic()
while time.monotonic()-start<180:
 try:
  if adb('shell','getprop','sys.boot_completed')=='1':break
 except Exception:pass
 time.sleep(3)
else:raise AssertionError('Boot timed out')
adb('shell','input','keyevent','82')
while time.monotonic()-start<230:
 if adb('shell','settings','get','global','adb_wifi_enabled')=='1':break
 time.sleep(2)
else:raise AssertionError('Boot recovery timed out')
s=adb('shell','dumpsys','activity','services',PKG);assert 'isForeground=true' in s
(P/'after-reboot-services.txt').write_text(s,encoding='utf8')
r=json.loads((P/'runtime-results.json').read_text());r.append({'test':'real emulator reboot recovery and foreground service','passed':True,'seconds':round(time.monotonic()-start,1)});(P/'runtime-results.json').write_text(json.dumps(r,indent=2));print(r[-1],flush=True)
adb('shell','am','start','-n',PKG+'/.MainActivity');time.sleep(2);dump('reboot-success');screenshot('reboot-success');(P/'crash-log.txt').write_text(adb('logcat','-d','-b','crash'),encoding='utf8')
