[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!$OutputDirectory){$OutputDirectory=Join-Path $root "work\releases\v$Version"}
New-Item -ItemType Directory -Force -Path $OutputDirectory|Out-Null
[xml]$project=Get-Content -LiteralPath (Join-Path $root 'src\ScrcpyGui\ScrcpyGui.csproj') -Raw
if($project.Project.PropertyGroup.Version -ne $Version){throw 'Project version differs from release version'}
& (Join-Path $root 'publish-wpf.ps1')
if($LASTEXITCODE -ne 0){throw 'Publish failed'}
$exe=Join-Path $root 'app\ScrcpyGui.exe';$apk=Join-Path $root 'app\android\BlinkLink-0.3.2-debug.apk'
if((Get-Item -LiteralPath $exe).VersionInfo.FileVersion -ne "$Version.0"){throw 'Published executable version mismatch'}
if((Get-FileHash -LiteralPath $apk).Hash.ToLowerInvariant() -ne 'affd1245bc6e150ee0c1ffd2ea18e0eaa0231fac66483002819c0419841cce61'){throw 'APK hash differs from verified 0.3.2 build'}
$stage=Join-Path $OutputDirectory ('package-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $stage,(Join-Path $stage 'android')|Out-Null
Copy-Item -LiteralPath $exe -Destination (Join-Path $stage 'ScrcpyGui.exe')
Copy-Item -LiteralPath $apk -Destination (Join-Path $stage 'android\BlinkLink-0.3.2-debug.apk')
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $stage 'LICENSE.txt')
$desktop=Get-Content -LiteralPath (Join-Path $root 'scrcpy-install-guide.html') -Raw
$desktop.Replace('android/manual.html','android/BlinkLink-guide.html')|Set-Content -LiteralPath (Join-Path $stage 'scrcpy-install-guide.html') -Encoding utf8
$mobile=Get-Content -LiteralPath (Join-Path $root 'android\manual.html') -Raw
$mobile.Replace('../app/android/BlinkLink-0.3.2-debug.apk','BlinkLink-0.3.2-debug.apk')|Set-Content -LiteralPath (Join-Path $stage 'android\BlinkLink-guide.html') -Encoding utf8
@"
scrcpy 설정 GUI v$Version / Blink Link Android 0.3.2

1. ZIP 전체를 새 폴더에 풉니다.
2. 공식 scrcpy Windows 배포본을 별도로 준비합니다: https://github.com/Genymobile/scrcpy/releases/latest
3. ScrcpyGui.exe를 실행하고 설정에서 scrcpy.exe/adb.exe 위치를 지정합니다.
4. 휴대폰을 페어링/연결하고 새 창 실행을 누릅니다.
5. Blink Link는 상단 'Blink Link 설정' → 대상 선택 → '이 휴대폰에 설치 · 권한 설정'으로 준비합니다.

PC 설명서: scrcpy-install-guide.html
휴대폰 설명서: android/BlinkLink-guide.html
.NET과 Blink Link APK는 PC 실행 파일에 포함됩니다. scrcpy/adb 자체는 포함하지 않습니다.
기존 사용자는 개인 설정 JSON을 보존하세요. APK는 개발 서명 개인 시험 버전입니다.
삼성 실기·절전·실제 음성 출력은 별도 검증 범위입니다.
"@|Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Encoding utf8
$zip=Join-Path $OutputDirectory "ScrcpyGui-v$Version-win-x64.zip"
Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $stage|ForEach-Object FullName) -DestinationPath $zip -Force
foreach($pair in @(@('ScrcpyGui.exe','ScrcpyGui.exe'),@('android\BlinkLink-0.3.2-debug.apk','BlinkLink-0.3.2-debug.apk'),@('scrcpy-install-guide.html','scrcpy-install-guide.html'),@('android\BlinkLink-guide.html','BlinkLink-guide.html'))){Copy-Item -LiteralPath (Join-Path $stage $pair[0]) -Destination (Join-Path $OutputDirectory $pair[1])}
$names=@('ScrcpyGui.exe',"ScrcpyGui-v$Version-win-x64.zip",'BlinkLink-0.3.2-debug.apk','scrcpy-install-guide.html','BlinkLink-guide.html')
$lines=foreach($name in $names){$hash=(Get-FileHash -LiteralPath (Join-Path $OutputDirectory $name)).Hash.ToLowerInvariant();"$hash  $name"}
$lines|Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Encoding ascii
Write-Output "Release package: $OutputDirectory"
