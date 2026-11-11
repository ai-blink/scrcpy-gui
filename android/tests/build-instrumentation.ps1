$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sdk=Join-Path $root 'work\android-lab\sdk'
$jdk=Join-Path $root 'work\android-lab\jdk'
$bt=Join-Path $sdk 'build-tools\36.0.0'
$platform=Join-Path $sdk 'platforms\android-36\android.jar'
$b=Join-Path $root ('android\build\macro-tests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force "$b\classes","$b\dex" | Out-Null
function Run([string]$exe,[string[]]$arguments){ & $exe @arguments; if($LASTEXITCODE -ne 0){throw "Failed: $exe"} }
# Compile app classes only as references; do not package them into the test APK.
$app=Join-Path $b 'app';New-Item -ItemType Directory $app | Out-Null
$sources=@(Get-ChildItem "$root\android\src" -Recurse -Filter '*.java' | ForEach-Object FullName)
Run "$jdk\bin\javac.exe" (@('-encoding','UTF-8','-source','8','-target','8','-Xlint:-options','-cp',$platform,'-d',$app)+$sources)
$testSources=@(Get-ChildItem "$PSScriptRoot\instrumentation" -Filter '*.java' | ForEach-Object FullName)
Run "$jdk\bin\javac.exe" (@('-encoding','UTF-8','-source','8','-target','8','-Xlint:-options','-cp',"$platform;$app",'-d',"$b\classes")+$testSources)
Run "$bt\aapt2.exe" @('link','-I',$platform,'--manifest',"$PSScriptRoot\instrumentation\AndroidManifest.xml",'-o',"$b\base.apk")
$classes=@(Get-ChildItem "$b\classes" -Recurse -Filter '*.class' | ForEach-Object FullName)
Run "$jdk\bin\java.exe" (@('-cp',"$bt\lib\d8.jar",'com.android.tools.r8.D8','--lib',$platform,'--classpath',$app,'--min-api','30','--output',"$b\dex")+$classes)
Run "$jdk\bin\jar.exe" @('uf',"$b\base.apk",'-C',"$b\dex",'classes.dex')
Run "$bt\zipalign.exe" @('-f','4',"$b\base.apk","$b\aligned.apk")
$out=Join-Path $root 'work\android-lab\macro-tests.apk'
Run "$jdk\bin\java.exe" @('-jar',"$bt\lib\apksigner.jar",'sign','--ks',"$root\work\android-lab\blinklink-debug.jks",'--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android','--out',$out,"$b\aligned.apk")
Write-Output $out
