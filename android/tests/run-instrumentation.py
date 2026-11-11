"""Run the separate test APK only against the guarded dedicated Android emulator."""
import subprocess
import lab_ui as lab
lab.validate_target()
for apk in [lab.ROOT/'app/android/BlinkLink-0.3.2-debug.apk',lab.ROOT/'work/android-lab/macro-tests.apk']:
    if not apk.exists():raise RuntimeError('Build APK first: '+str(apk))
    print(lab.adb('install','-r',str(apk)),flush=True)
lab.adb('shell','pm','grant',lab.PKG,'android.permission.POST_NOTIFICATIONS')
lab.validate_target()
r=subprocess.run([lab.ADB,'-s',lab.SER,'shell','am','instrument','-w','kr.blinklabs.blinklink.tests/kr.blinklabs.blinklink.tests.MacroInstrumentation'],capture_output=True,timeout=240)
output=r.stdout.decode('utf8',errors='replace')
p=lab.ROOT/'work/android-lab/review-031';p.mkdir(exist_ok=True)
(p/'instrumentation.txt').write_text(output,encoding='utf8')
print(output)
assert r.returncode==0 and 'PASS 38 instrumentation assertions' in output and 'FAIL ' not in output
