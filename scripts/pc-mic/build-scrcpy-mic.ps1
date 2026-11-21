# PC 마이크 → 폰 주입(scrcpy PR #7004) 수정판 scrcpy를 빌드해 C:\app\scrcpy-mic-test 에 둔다.
# PC 쪽 scrcpy.exe = WSL Ubuntu-24.04 에서 공식 release/build_windows.sh 64 로 크로스 빌드
# 폰 쪽 scrcpy-server = Windows 에서 저장소 work\android-lab 의 JDK 17 + Android SDK 36 으로 gradle 빌드
# 시험용 wav 파일을 넣을 수 있게 FFmpeg에 wav 읽기(--enable-demuxer=wav)를 켠다. 실제 마이크(DirectShow) 경로와는 무관하다.
param(
    [string]$Distro = 'Ubuntu-24.04',
    [string]$Output = 'C:\app\scrcpy-mic-test'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$serverSrc = Join-Path $repo 'work\scrcpy-pr7004'

# 1) PC 쪽 (WSL)
$wsl = @'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q meson ninja-build nasm cmake mingw-w64 mingw-w64-tools libz-mingw-w64-dev pkg-config autoconf automake libtool curl xz-utils unzip git
mkdir -p /root/build && cd /root/build
if [ ! -d scrcpy-pr7004 ]; then
  git clone -q https://github.com/Genymobile/scrcpy.git scrcpy-pr7004
fi
cd scrcpy-pr7004
git fetch -q origin pull/7004/head:pr7004 || true
git checkout -q pr7004
grep -q 'enable-demuxer=wav' app/deps/ffmpeg.sh || sed -i 's/        --enable-demuxer=image2/        --enable-demuxer=image2\n        --enable-demuxer=wav/' app/deps/ffmpeg.sh
release/build_windows.sh 64
git rev-parse --short HEAD
'@
wsl.exe -d $Distro -u root -- bash -lc ($wsl -replace "`r", '')
if ($LASTEXITCODE -ne 0) { throw "WSL 빌드 실패 ($LASTEXITCODE)" }

# 2) 폰 쪽 (Windows gradle) — PC 쪽과 같은 커밋이어야 버전 문자열이 맞는다.
if (-not (Test-Path $serverSrc)) {
    git clone -q https://github.com/Genymobile/scrcpy.git $serverSrc
}
git -C $serverSrc fetch -q origin pull/7004/head:pr7004
git -C $serverSrc checkout -q pr7004
$env:JAVA_HOME = Join-Path $repo 'work\android-lab\jdk'
$env:ANDROID_HOME = Join-Path $repo 'work\android-lab\sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
Push-Location $serverSrc
try { & .\gradlew.bat --no-daemon -q -p server assembleRelease; if ($LASTEXITCODE -ne 0) { throw "서버 빌드 실패 ($LASTEXITCODE)" } }
finally { Pop-Location }

# 3) 모으기
New-Item -ItemType Directory -Force $Output | Out-Null
Copy-Item "\\wsl.localhost\$Distro\root\build\scrcpy-pr7004\release\work\build-win64\dist\*" $Output -Recurse -Force
Copy-Item (Join-Path $serverSrc 'server\build\outputs\apk\release\server-release-unsigned.apk') (Join-Path $Output 'scrcpy-server') -Force
& (Join-Path $Output 'scrcpy.exe') --version | Select-Object -First 1
