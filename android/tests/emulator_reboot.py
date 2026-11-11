"""Require a new boot ID and actual OFF-to-ON recovery in the named AVD."""
from lab_ui import *

results=[]
def record(name, **details):
 result=dict(test=name,passed=True,**details);results.append(result)
 (P/'reboot-results.json').write_text(json.dumps(results,indent=2),encoding='utf8')
 print(result,flush=True)

validate_target();resume()
adb('shell','cmd','location','set-location-enabled','false')
adb('shell','settings','put','global','adb_wifi_enabled','0');assert_off_for(3)
old_boot=adb('shell','cat','/proc/sys/kernel/random/boot_id');assert old_boot
adb('reboot');start=time.monotonic()
while time.monotonic()-start<180:
 try:
  validate_target()
  new_boot=raw('shell','cat','/proc/sys/kernel/random/boot_id')
  if new_boot and new_boot!=old_boot and raw('shell','getprop','sys.boot_completed')=='1':break
 except (RuntimeError,IndexError,subprocess.TimeoutExpired):pass
 time.sleep(3)
else:raise AssertionError('New boot ID and completed boot not observed')
adb('shell','input','keyevent','82')
deadline=time.monotonic()+30
while time.monotonic()<deadline and not foreground():time.sleep(1)
assert foreground(), 'Boot receiver must start monitor without opening activity'
assert adb('shell','settings','get','global','adb_wifi_enabled')=='0'
(P/'after-reboot-services.txt').write_text(adb('shell','dumpsys','activity','services',PKG))
adb('shell','cmd','location','set-location-enabled','true');wait_on()
record('new boot ID, foreground boot service and OFF-to-ON recovery',old_boot=old_boot,new_boot=new_boot,seconds=round(time.monotonic()-start,1))

adb('shell','svc','wifi','disable');assert_off_for(5)
adb('shell','svc','wifi','enable');seconds=wait_on();record('WiFi reconnect recovery',seconds=seconds)
adb('shell','cmd','location','set-location-enabled','false')
adb('shell','settings','put','global','adb_wifi_enabled','0');assert_off_for(33)
record('unknown network identity blocks enabling')
adb('shell','cmd','location','set-location-enabled','true');wait_on();record('location restoration recovery')
show_app();click('자동 복구 일시정지')
adb('shell','settings','put','global','adb_wifi_enabled','0');assert_off_for(33)
record('pause blocks automatic enabling');assert not foreground()
adb('shell','settings','put','global','adb_wifi_enabled','1')
time.sleep(3);assert adb('shell','settings','get','global','adb_wifi_enabled')=='1'
record('paused app preserves externally enabled debugging')
resume();show_app();dump('reboot-final');screenshot('reboot-final')
(P/'crash-log.txt').write_text(adb('logcat','-d','-b','crash'),encoding='utf8')
