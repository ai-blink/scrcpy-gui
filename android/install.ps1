param(
    [Parameter(Mandatory=$true)][string]$Serial,
    [string]$Adb = 'C:\app\scrcpy-win64-v4.1\adb.exe',
    [switch]$GrantPermission
)
$ErrorActionPreference = 'Stop'
$apk = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\app\android\BlinkLink-0.2.0-debug.apk'))
if (!(Test-Path -LiteralPath $apk)) { throw 'APK가 없습니다. 먼저 build.ps1을 실행하세요.' }
& $Adb -s $Serial get-state
if ($LASTEXITCODE -ne 0) { throw '지정한 기기가 연결되지 않았습니다. PC와 먼저 페어링하세요.' }
& $Adb -s $Serial install -r $apk
if ($LASTEXITCODE -ne 0) { throw '설치에 실패했습니다.' }
if ($GrantPermission) {
    & $Adb -s $Serial shell pm grant kr.blinklabs.blinklink android.permission.WRITE_SECURE_SETTINGS
    if ($LASTEXITCODE -ne 0) { throw '권한 부여에 실패했습니다. 기기의 보안 정책을 확인하세요.' }
}
Write-Output '설치 완료. 휴대폰에서 Blink Link를 열고 사용할 Wi-Fi와 자동 복구를 설정하세요.'
