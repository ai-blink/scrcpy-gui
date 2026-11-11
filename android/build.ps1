param(
    [string]$Sdk = "$PSScriptRoot\..\work\android-lab\sdk",
    [string]$JavaHome = "$PSScriptRoot\..\work\android-lab\jdk"
)
$ErrorActionPreference = 'Stop'
$Sdk = (Resolve-Path -LiteralPath $Sdk).Path
$JavaHome = (Resolve-Path -LiteralPath $JavaHome).Path
$env:JAVA_HOME = $JavaHome
$bt = Join-Path $Sdk 'build-tools\36.0.0'
$platform = Join-Path $Sdk 'platforms\android-36\android.jar'
$build = Join-Path $PSScriptRoot ('build\run-' + [Guid]::NewGuid().ToString('N'))
$out = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\app\android'))
New-Item -ItemType Directory -Force $build,"$build\classes","$build\dex","$build\tests",$out | Out-Null
function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Failed ($LASTEXITCODE): $Exe" }
}
$sources = @(Get-ChildItem -LiteralPath "$PSScriptRoot\src" -Recurse -Filter '*.java' | ForEach-Object FullName)
Invoke-Checked "$JavaHome\bin\javac.exe" (@('-encoding','UTF-8','-source','8','-target','8','-Xlint:-options','-classpath',$platform,'-d',"$build\classes") + $sources)
$testSources = @(Get-ChildItem -LiteralPath "$PSScriptRoot\tests" -Filter '*Test.java' | ForEach-Object FullName)
Invoke-Checked "$JavaHome\bin\javac.exe" (@('-encoding','UTF-8','-d',"$build\tests","$PSScriptRoot\src\kr\blinklabs\blinklink\RecoveryPolicy.java","$PSScriptRoot\src\kr\blinklabs\blinklink\RetryBudget.java") + $testSources)
Invoke-Checked "$JavaHome\bin\java.exe" @('-cp',"$build\tests",'RecoveryPolicyTest')
Invoke-Checked "$JavaHome\bin\java.exe" @('-cp',"$build\tests",'RetryBudgetTest')
Invoke-Checked "$bt\aapt2.exe" @('link','-I',$platform,'--manifest',"$PSScriptRoot\AndroidManifest.xml",'-o',"$build\base.apk")
$classes = @(Get-ChildItem -LiteralPath "$build\classes" -Recurse -Filter '*.class' | ForEach-Object FullName)
# Call D8 through Java to avoid cmd.exe argument limits and shell quoting.
Invoke-Checked "$JavaHome\bin\java.exe" (@('-cp',"$bt\lib\d8.jar",'com.android.tools.r8.D8','--lib',$platform,'--min-api','30','--output',"$build\dex") + $classes)
Invoke-Checked "$JavaHome\bin\jar.exe" @('uf',"$build\base.apk",'-C',"$build\dex",'classes.dex')
Invoke-Checked "$bt\zipalign.exe" @('-f','4',"$build\base.apk","$build\aligned.apk")
$key = Join-Path $PSScriptRoot '..\work\android-lab\blinklink-debug.jks'
New-Item -ItemType Directory -Force (Split-Path -Parent $key) | Out-Null
if (!(Test-Path -LiteralPath $key)) {
    Invoke-Checked "$JavaHome\bin\keytool.exe" @('-genkeypair','-keystore',$key,'-storepass','android','-keypass','android','-alias','androiddebugkey','-dname','CN=Android Debug,O=Android,C=US','-keyalg','RSA','-keysize','2048','-validity','10000')
}
$apk = Join-Path $out 'BlinkLink-0.2.0-debug.apk'
Invoke-Checked "$JavaHome\bin\java.exe" @('-jar',"$bt\lib\apksigner.jar",'sign','--ks',$key,'--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android','--out',$apk,"$build\aligned.apk")
Invoke-Checked "$JavaHome\bin\java.exe" @('-jar',"$bt\lib\apksigner.jar",'verify','--verbose',$apk)
Get-FileHash -LiteralPath $apk -Algorithm SHA256
