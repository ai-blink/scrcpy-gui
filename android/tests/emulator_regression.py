"""Dedicated prepared AVD: actual APK replacement, stop/resume and rate limiting."""
from lab_ui import *

results=[]
def record(name, **details):
 result=dict(test=name,passed=True,**details);results.append(result)
 (P/'runtime-results.json').write_text(json.dumps(results,indent=2),encoding='utf8')
 print(result,flush=True)

validate_target()
# Fixture precondition: start with ON and a fresh boot's unused automatic budget.
adb('shell','settings','put','global','adb_wifi_enabled','1')
resume()
old_pid=adb('shell','pidof',PKG)
# Block the old service while forcing the flag OFF before the actual update.
adb('shell','cmd','location','set-location-enabled','false');time.sleep(2)
adb('shell','settings','put','global','adb_wifi_enabled','0');assert_off_for(3)
apk=ROOT/'app'/'android'/'BlinkLink-0.3.2-debug.apk'
assert 'Success' in adb('install','-r',str(apk))
deadline=time.monotonic()+30
while time.monotonic()<deadline and not foreground():time.sleep(1)
assert foreground(), 'Replacement must start service before opening the activity'
new_pid=adb('shell','pidof',PKG)
assert old_pid and new_pid and old_pid!=new_pid
assert 'versionName=0.3.2' in adb('shell','dumpsys','package',PKG)
(P/'after-update-services.txt').write_text(adb('shell','dumpsys','activity','services',PKG))
adb('shell','cmd','location','set-location-enabled','true');seconds=wait_on()
record('actual APK replacement, new process and OFF-to-ON recovery',old_pid=old_pid,new_pid=new_pid,seconds=seconds)

adb('shell','am','force-stop',PKG)
adb('shell','settings','put','global','adb_wifi_enabled','0')
show_app();tree=dump('stopped-reopened')
assert any('감시 중단' in n.get('text','') for n in tree.iter('node'))
assert not foreground();assert_off_for(5);screenshot('stopped-reopened')
record('force-stop then reopen shows stopped, not running')
resume();wait_on();record('explicit restart resumes monitoring')

time.sleep(6);adb('shell','input','keyevent','3')
adb('shell','settings','put','global','adb_wifi_enabled','0')
wait_on();record('third automatic request works in background')
time.sleep(6);adb('shell','settings','put','global','adb_wifi_enabled','0')
assert_off_for(35);record('fourth automatic request blocked despite prior successful ON states')
adb('shell','am','force-stop',PKG)
resume();assert_off_for(8);record('automatic quota survives process restart')
click('지금 한 번 복구');wait_on();record('explicit manual recovery is available during cooldown')
dump('regression-final');screenshot('regression-final')
