# =============================================================
#  실행 파일 찾기 — PC 마다 설치 위치가 달라서 순서대로 뒤진다.
#   ① config 에 저장된 경로 (설정 탭에서 직접 지정한 것)
#   ② 이 스크립트와 같은 폴더 (scrcpy 폴더에 통째로 넣어 쓰는 경우)
#   ③ PATH
#   ④ 흔한 설치 위치 (winget / scoop / chocolatey / Program Files / Downloads / C:\app)
#  넷 다 실패하면 GUI 는 그대로 뜨고, '설정' 탭에서 직접 지정하도록 안내한다.
# =============================================================

$OFFICIAL_RELEASE_API = 'https://api.github.com/repos/Genymobile/scrcpy/releases/latest'
$OFFICIAL_RELEASES_URL = 'https://github.com/Genymobile/scrcpy/releases'
$DEFAULT_SCRCPY_INSTALL_ROOT = Join-Path $env:LOCALAPPDATA 'scrcpy-gui\scrcpy'

# Genymobile/scrcpy의 정식 최신 릴리스만 허용한다. URL 입력·제3자 미러는 받지 않는다.
function Get-OfficialScrcpyRelease {
    try {
        $release = Invoke-RestMethod -Uri $OFFICIAL_RELEASE_API -Headers @{ 'User-Agent' = 'scrcpy-gui' } -ErrorAction Stop
        $tag = [string]$release.tag_name
        if ($release.draft -or $release.prerelease -or $tag -notmatch '^v\d+\.\d+(?:\.\d+)?$') {
            throw '최신 정식 릴리스 정보를 확인할 수 없습니다.'
        }

        $assetName = "scrcpy-win64-$tag.zip"
        $assets = @($release.assets | Where-Object { $_.name -eq $assetName })
        if ($assets.Count -ne 1) { throw "공식 64비트 자산($assetName)을 찾지 못했습니다." }

        $asset = $assets[0]
        $downloadUrl = [string]$asset.browser_download_url
        $expectedUrl = "https://github.com/Genymobile/scrcpy/releases/download/$tag/$assetName"
        if ($downloadUrl -cne $expectedUrl) { throw '공식 GitHub 다운로드 경로가 아닙니다.' }

        $digest = [string]$asset.digest
        if ($digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { throw '공식 SHA-256 digest가 없습니다.' }
        if ([long]$asset.size -le 0) { throw '공식 자산의 크기가 올바르지 않습니다.' }

        return [pscustomobject]@{
            Tag         = $tag
            AssetName   = $assetName
            DownloadUrl = $downloadUrl
            Sha256      = $Matches[1].ToLowerInvariant()
            Size        = [long]$asset.size
        }
    } catch {
        throw "공식 scrcpy 릴리스 정보를 확인하지 못했습니다: $($_.Exception.Message)"
    }
}

# 검증된 ZIP도 해제 전 경로 이동(Zip Slip) 항목은 거부한다.
function Test-SafeZipEntries {
    param([string]$ZipPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('/', '\')
            if ([System.IO.Path]::IsPathRooted($name) -or
                $name -match '(^|\\)\.\.(\\|$)' -or
                $name -match '^[A-Za-z]:') {
                throw "안전하지 않은 압축 경로가 포함되어 있습니다: $($entry.FullName)"
            }
        }
    } finally {
        $archive.Dispose()
    }
}

function Resolve-ScrcpyInstallRoot {
    param([string]$Value)

    $candidate = if ($Value) { $Value.Trim() } else { '' }
    if (-not $candidate) { $candidate = $DEFAULT_SCRCPY_INSTALL_ROOT }
    try {
        return [System.IO.Path]::GetFullPath($candidate)
    } catch {
        throw "설치 폴더 경로가 올바르지 않습니다: $candidate"
    }
}

function Get-ExeCandidates {
    param([string]$Name, [string[]]$Globs)
    $list = [System.Collections.Generic.List[string]]::new()

    $side = Join-Path $ProjectRoot "$Name.exe"
    if (Test-Path $side) { $list.Add($side) }

    $onPath = (Get-Command $Name -ErrorAction SilentlyContinue).Source
    if ($onPath) { $list.Add($onPath) }

    foreach ($g in $Globs) {
        if (-not $g) { continue }
        foreach ($hit in (Get-ChildItem -Path $g -ErrorAction SilentlyContinue |
                          Sort-Object LastWriteTime -Descending | Select-Object -First 3)) {
            $list.Add($hit.FullName)
        }
    }
    return ($list | Select-Object -Unique | Select-Object -First 8)
}

function Get-ScrcpyVersion {
    param([string]$Path)
    try {
        $line = & $Path --version 2>$null | Select-Object -First 1
        if ($line -match 'scrcpy\s+(\d+)\.(\d+)(?:\.(\d+))?') {
            $patch = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
            return [version]::new([int]$Matches[1], [int]$Matches[2], $patch)
        }
    } catch { }
    return $null
}

# ⚠️ 순서로 고르면 안 된다 — 구버전이 PATH 에 남아 있는 경우가 흔하다(실측: PATH=3.3.2, 옆에 4.1).
#    후보를 전부 모아 **버전이 가장 높은 것**을 고른다. 사람이 직접 지정한 경로는 그대로 존중.
function Find-Scrcpy {
    param([string]$ConfigValue, [string[]]$Globs)
    if ($ConfigValue -and (Test-Path $ConfigValue)) { return $ConfigValue }

    $cands = Get-ExeCandidates -Name 'scrcpy' -Globs $Globs
    if (-not $cands) { return $null }

    $best = $null; $bestVer = $null
    foreach ($c in $cands) {
        $v = Get-ScrcpyVersion $c
        if ($v -and (-not $bestVer -or $v -gt $bestVer)) { $best = $c; $bestVer = $v }
    }
    if ($best) { return $best }
    return @($cands)[0]
}

function Find-Adb {
    param([string]$ConfigValue, [string[]]$Globs)
    if ($ConfigValue -and (Test-Path $ConfigValue)) { return $ConfigValue }
    $cands = Get-ExeCandidates -Name 'adb' -Globs $Globs
    if ($cands) { return @($cands)[0] }   # adb 는 하위호환이라 버전 비교 불필요
    return $null
}

$SCRCPY_GLOBS = @(
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Genymobile.scrcpy*\*\scrcpy.exe"
    "$env:USERPROFILE\scoop\apps\scrcpy\current\scrcpy.exe"
    "C:\ProgramData\chocolatey\lib\scrcpy\tools\*\scrcpy.exe"
    "$env:ProgramFiles\scrcpy*\scrcpy.exe"
    "${env:ProgramFiles(x86)}\scrcpy*\scrcpy.exe"
    "C:\app\scrcpy*\scrcpy.exe"
    "$env:USERPROFILE\Downloads\scrcpy*\scrcpy.exe"
    "$env:USERPROFILE\Desktop\scrcpy*\scrcpy.exe"
)
$SCRCPY_EXE = Find-Scrcpy -ConfigValue $script:Config.scrcpyPath -Globs $SCRCPY_GLOBS
$SCRCPY_DIR = if ($SCRCPY_EXE) { Split-Path $SCRCPY_EXE -Parent } else { $ProjectRoot }
$SCRCPY_VER = if ($SCRCPY_EXE) { Get-ScrcpyVersion $SCRCPY_EXE } else { $null }

# adb 는 scrcpy 공식 배포판에 같이 들어 있는 경우가 많아 scrcpy 폴더를 먼저 본다.
$ADB_GLOBS = @(
    $(if ($SCRCPY_DIR) { Join-Path $SCRCPY_DIR 'adb.exe' })
    "C:\app\adb\adb.exe"
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
    "$env:ProgramFiles\Android\platform-tools\adb.exe"
    "$env:USERPROFILE\scoop\apps\adb\current\adb.exe"
    "C:\ProgramData\chocolatey\lib\adb\tools\*\adb.exe"
    "C:\app\scrcpy*\adb.exe"
)
$ADB_EXE = Find-Adb -ConfigValue $script:Config.adbPath -Globs $ADB_GLOBS
if (-not $ADB_EXE) { $ADB_EXE = 'adb' }   # 마지막 수단: PATH 에 있길 기대

# 다운로드는 이 버튼을 누른 뒤 확인 대화상자에서 다시 승인해야만 시작한다.
# 기존 설치 경로는 건드리지 않고 사용자 프로필 아래의 버전별 새 폴더만 사용한다.
function Install-OfficialScrcpy {
    try {
        $release = Get-OfficialScrcpyRelease
    } catch {
        $LblStatus.Text = '공식 릴리스 정보를 확인하지 못했습니다.'
        [void][Windows.MessageBox]::Show($_.Exception.Message, 'scrcpy 설치', 'OK', 'Error')
        return
    }

    try {
        $installRoot = Resolve-ScrcpyInstallRoot $script:InstallRootBox.Text
    } catch {
        [void][Windows.MessageBox]::Show($_.Exception.Message, 'scrcpy 설치', 'OK', 'Error')
        return
    }
    $targetDir = Join-Path $installRoot $release.Tag
    if (Test-Path -LiteralPath $targetDir) {
        [void][Windows.MessageBox]::Show(
            "$($release.Tag) 설치 폴더가 이미 있습니다.`n`n기존 파일을 덮어쓰지 않기 위해 설치하지 않았습니다.`n설정 탭의 [찾아보기]로 사용할 scrcpy.exe를 선택할 수 있습니다.`n`n경로: $targetDir",
            'scrcpy 설치', 'OK', 'Information')
        return
    }

    $sizeMiB = [math]::Round($release.Size / 1MB, 1)
    $approved = [Windows.MessageBox]::Show(
        "공식 scrcpy $($release.Tag)를 설치합니다.`n`n" +
        "파일: $($release.AssetName) ($sizeMiB MiB / $($release.Size.ToString('N0')) 바이트)`n" +
        "출처: $OFFICIAL_RELEASES_URL`n" +
        "SHA-256: $($release.Sha256)`n" +
        "설치 경로: $targetDir`n`n" +
        "[예]를 누르면 Genymobile의 공식 GitHub 릴리스에서만 다운로드하고, SHA-256 검증에 성공한 ZIP만 새 폴더에 압축 해제합니다.`n" +
        "기존 scrcpy 설치를 덮어쓰거나 자동 실행하지 않습니다.",
        '공식 scrcpy 설치 확인', 'YesNo', 'Question')
    if ($approved -ne [Windows.MessageBoxResult]::Yes) { return }

    $token = [guid]::NewGuid().ToString('N')
    $tempRoot = [System.IO.Path]::GetTempPath()
    $zipPath = Join-Path $tempRoot "scrcpy-gui-$($release.Tag)-$token.zip"
    $stageDir = Join-Path $tempRoot "scrcpy-gui-$($release.Tag)-$token"

    try {
        $LblStatus.Text = "공식 scrcpy $($release.Tag) 다운로드 중..."
        Invoke-WebRequest -Uri $release.DownloadUrl -OutFile $zipPath -Headers @{ 'User-Agent' = 'scrcpy-gui' } -ErrorAction Stop

        $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        if ($actualHash -cne $release.Sha256) {
            throw "SHA-256 검증 실패: 기대 $($release.Sha256), 실제 $actualHash"
        }

        Test-SafeZipEntries -ZipPath $zipPath
        New-Item -ItemType Directory -Path $stageDir -ErrorAction Stop | Out-Null
        Expand-Archive -LiteralPath $zipPath -DestinationPath $stageDir -ErrorAction Stop

        $scrcpyFiles = @(Get-ChildItem -LiteralPath $stageDir -Filter 'scrcpy.exe' -File -Recurse -ErrorAction Stop)
        if ($scrcpyFiles.Count -ne 1) { throw '압축 해제 결과에서 scrcpy.exe를 하나만 확인할 수 없습니다.' }

        $stagedScrcpy = $scrcpyFiles[0].FullName
        $stagedAdb = Join-Path (Split-Path $stagedScrcpy -Parent) 'adb.exe'
        if (-not (Test-Path -LiteralPath $stagedAdb)) { throw '압축 해제 결과에서 adb.exe를 찾지 못했습니다.' }
        $relativeScrcpy = [System.IO.Path]::GetRelativePath($stageDir, $stagedScrcpy)
        $relativeAdb = [System.IO.Path]::GetRelativePath($stageDir, $stagedAdb)

        New-Item -ItemType Directory -Path $installRoot -Force -ErrorAction Stop | Out-Null
        Move-Item -LiteralPath $stageDir -Destination $targetDir -ErrorAction Stop
        $stageDir = $null

        # Move-Item 뒤에는 임시 경로가 아닌 새 설치 경로를 config에 기록한다.
        $installedScrcpy = Join-Path $targetDir $relativeScrcpy
        $installedAdb = Join-Path $targetDir $relativeAdb
        if (-not (Test-Path -LiteralPath $installedScrcpy) -or -not (Test-Path -LiteralPath $installedAdb)) {
            throw '설치 후 scrcpy.exe 또는 adb.exe를 확인하지 못했습니다.'
        }

        $script:SCRCPY_EXE = $installedScrcpy
        $script:SCRCPY_DIR = Split-Path $installedScrcpy -Parent
        $script:SCRCPY_VER = Get-ScrcpyVersion $installedScrcpy
        $script:ADB_EXE = $installedAdb
        $script:Config['scrcpyPath'] = $installedScrcpy
        $script:Config['adbPath'] = $installedAdb
        $script:Config['installRoot'] = $installRoot
        $configSaved = Write-Config $script:Config

        $Controls['scrcpyPath'].Text = $installedScrcpy
        $Controls['adbPath'].Text = $installedAdb
        if ($configSaved) {
            $LblStatus.Text = "공식 scrcpy $($release.Tag) 설치·검증 완료 — 폰에서 무선 디버깅을 켠 뒤 상단 [무선 페어링]을 누르세요."
        } else {
            $LblStatus.Text = "설치는 완료됐지만 경로 저장에 실패했습니다 — 설정 탭에서 경로를 다시 지정하세요."
        }
    } catch {
        $LblStatus.Text = '공식 scrcpy 설치에 실패했습니다.'
        [void][Windows.MessageBox]::Show("설치 실패:`n$($_.Exception.Message)", 'scrcpy 설치', 'OK', 'Error')
    } finally {
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue }
        if ($stageDir -and (Test-Path -LiteralPath $stageDir)) {
            $safeTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
            $safeStageDir = [System.IO.Path]::GetFullPath($stageDir)
            if ($safeStageDir.StartsWith($safeTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
