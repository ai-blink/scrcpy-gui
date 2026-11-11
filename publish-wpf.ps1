[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'src\ScrcpyGui\ScrcpyGui.csproj'
$output = Join-Path $PSScriptRoot 'app'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '.NET 8 SDK를 찾지 못했습니다. https://dotnet.microsoft.com/download/dotnet/8.0 에서 설치한 뒤 다시 실행하세요.'
}

$apk = Join-Path $PSScriptRoot 'app\android\BlinkLink-0.3.1-debug.apk'
if (!(Test-Path -LiteralPath $apk)) {
    & (Join-Path $PSScriptRoot 'android\build.ps1')
    if (!(Test-Path -LiteralPath $apk)) { throw 'Blink Link APK를 만들지 못했습니다. Android SDK/JDK 경로를 확인하세요.' }
}
& dotnet publish $project -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    --output $output --nologo
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "빌드 완료: $output\ScrcpyGui.exe"
