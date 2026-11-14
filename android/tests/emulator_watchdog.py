"""Watchdog job revives the monitor after an OS kill but never after a user stop (BlinkLink16 only)."""
from lab_ui import *

results=[]
def record(name, **details):
 result=dict(test=name,passed=True,**details);results.append(result)
 (P/'watchdog-results.json').write_text(json.dumps(results,indent=2,ensure_ascii=False),encoding='utf8')
 print(result,flush=True)
def job_pending():
 validate_target()
 state=subprocess.run([ADB,'-s',SER,'shell','cmd','jobscheduler','get-job-state',PKG,'41'],capture_output=True,text=True)
 return 'unknown' not in state.stdout
def run_job():
 """Force the job; returns False when it is not scheduled (e.g. after pause)."""
 validate_target()
 r=subprocess.run([ADB,'-s',SER,'shell','cmd','jobscheduler','run','-f',PKG,'41'],capture_output=True,text=True)
 time.sleep(4);return 'Could not find job' not in r.stdout+r.stderr
def pid():
 validate_target()
 return subprocess.run([ADB,'-s',SER,'shell','pidof',PKG],capture_output=True,text=True).stdout.strip()

validate_target(require_package=False)
apk=ROOT/'app'/'android'/'BlinkLink-0.4.0-debug.apk'
assert raw('install','-r',str(apk)).splitlines()[-1]=='Success'
for perm in ['ACCESS_COARSE_LOCATION','ACCESS_FINE_LOCATION','ACCESS_BACKGROUND_LOCATION','POST_NOTIFICATIONS','WRITE_SECURE_SETTINGS']:
 adb('shell','pm','grant',PKG,'android.permission.'+perm)
adb('shell','cmd','location','set-location-enabled','true')
was_whitelisted=PKG in adb('shell','dumpsys','deviceidle','whitelist')
adb('shell','dumpsys','deviceidle','whitelist','+'+PKG)  # phone setting: battery "unrestricted"
resume()
assert foreground() and job_pending();record('start schedules watchdog')

before=pid()
adb('shell','pm','revoke',PKG,'android.permission.ACCESS_BACKGROUND_LOCATION');time.sleep(3)
adb('shell','pm','grant',PKG,'android.permission.ACCESS_BACKGROUND_LOCATION');time.sleep(8)
exits=adb('shell','dumpsys','activity','exit-info',PKG)
assert pid()!=before and 'PERMISSION CHANGE' in exits.split('ApplicationExitInfo #1')[0]
# AOSP restarts the sticky service here; the Samsung phone stayed dead for 39 h (11-12 22:19 → 11-14 13:18).
record('permission change kills monitor',aosp_restarted=foreground())
# Reproduce the phone's "stayed dead" state: stop only the service (root shell), leaving "enabled" on.
raw('root');time.sleep(4);raw('wait-for-device');resume()
validate_target()
stop=subprocess.run([ADB,'-s',SER,'shell','am','stopservice','-n',PKG+'/.LinkService'],capture_output=True,text=True)
assert 'Service stopped' in stop.stdout+stop.stderr, stop;time.sleep(3)
assert not foreground() and job_pending();record('monitor dead while enabled (phone state reproduced)')
assert run_job() and foreground();record('watchdog revives monitor')

show_app();click('자동 복구 일시정지');time.sleep(2)
assert not foreground() and not job_pending();record('pause cancels watchdog')
run_job();assert not foreground();record('paused monitor stays stopped')

resume();assert job_pending()
adb('shell','am','force-stop',PKG);time.sleep(2)
adb('shell','am','start','-n',PKG+'/.MainActivity');time.sleep(3)
assert not foreground()
run_job();assert not foreground();record('user force-stop is not overridden by watchdog')

resume();assert foreground() and job_pending()
if not was_whitelisted:adb('shell','dumpsys','deviceidle','whitelist','-'+PKG)
adb('shell','cmd','appops','set',PKG,'RUN_ANY_IN_BACKGROUND','allow')
raw('unroot');time.sleep(4);raw('wait-for-device')
(P/'watchdog-crash-log.txt').write_text(adb('logcat','-d','-b','crash'),encoding='utf8')
record('final state restored',crash_lines=len(adb('logcat','-d','-b','crash').splitlines()))
