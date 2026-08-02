param(
    [switch]$ValidateOnly
)

# =============================================================
#  scrcpy 설정 GUI  v0.1.5-beta   (Windows / PowerShell 7 + WPF)
#  https://github.com/ai-blink/scrcpy-gui                MIT License
#
#  ★ 옵션을 추가/변경하려면 아래 $OPTIONS 표에 한 줄만 넣으면 됩니다.
#    화면은 이 표를 읽어서 자동으로 만들어집니다.
#
#    Group : 왼쪽 메뉴 어디에 넣을지 (없는 이름을 쓰면 메뉴가 새로 생김)
#    Key   : 고유 이름 (프리셋 저장용, 겹치지만 않으면 됨)
#    Label : 화면에 보일 이름
#    Type  : check(토글) / text(입력칸) / combo(선택목록) / phonepref(폰 설정) / path(실행 파일 경로)
#    Arg   : scrcpy에 넘길 인자.  text·combo는 {0} 자리에 값이 들어감
#    Items : combo일 때 목록.  '(기본)' 을 고르면 그 옵션은 안 붙음
#    Hint  : 오른쪽에 회색으로 보이는 설명
# =============================================================

# 설정 파일은 항상 이 스크립트 옆에 둔다 (저장소에서 돌리든 배포본에서 돌리든 일관)
$PRESET_FILE = Join-Path $PSScriptRoot 'scrcpy-gui-presets.json'
$LAST_FILE   = Join-Path $PSScriptRoot 'scrcpy-gui-last.json'   # 창 닫을 때 현재 값 자동 저장 → 다음에 켜면 복원
$CONFIG_FILE = Join-Path $PSScriptRoot 'scrcpy-gui-config.json' # scrcpy·adb 실행 파일 위치 (PC마다 다름)
$OFFICIAL_RELEASE_API = 'https://api.github.com/repos/Genymobile/scrcpy/releases/latest'
$OFFICIAL_RELEASES_URL = 'https://github.com/Genymobile/scrcpy/releases'
$DEFAULT_SCRCPY_INSTALL_ROOT = Join-Path $env:LOCALAPPDATA 'scrcpy-gui\scrcpy'

# =============================================================
#  실행 파일 찾기 — PC 마다 설치 위치가 달라서 순서대로 뒤진다.
#   ① config 에 저장된 경로 (설정 탭에서 직접 지정한 것)
#   ② 이 스크립트와 같은 폴더 (scrcpy 폴더에 통째로 넣어 쓰는 경우)
#   ③ PATH
#   ④ 흔한 설치 위치 (winget / scoop / chocolatey / Program Files / Downloads / C:\app)
#  넷 다 실패하면 GUI 는 그대로 뜨고, '설정' 탭에서 직접 지정하도록 안내한다.
# =============================================================

function Read-Config {
    if (Test-Path $CONFIG_FILE) {
        try { return Get-Content $CONFIG_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable } catch { }
    }
    return @{}
}

function Write-Config {
    param($Config)
    try {
        $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $CONFIG_FILE -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

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

    $side = Join-Path $PSScriptRoot "$Name.exe"
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

$script:Config = Read-Config

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
$SCRCPY_DIR = if ($SCRCPY_EXE) { Split-Path $SCRCPY_EXE -Parent } else { $PSScriptRoot }
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

if ($ValidateOnly) {
    Get-OfficialScrcpyRelease | ConvertTo-Json -Compress
    return
}

$OPTIONS = @(
    # ---------------- 화면 ----------------
    @{ Group='화면'; Key='max-size';       Label='해상도 상한';   Type='editcombo'; Default='1850'; Items=@('(기본)','3088','2560','1920','1850','1600','1440','1280','1080','720'); Arg='--max-size={0}'; Hint='긴 변 픽셀 하나만 넣습니다 (비율은 폰에 맞춰 자동).  3088=원본 · 1920=FHD(1080x1920) · 1440=HD+(810x1440) · 1080=(607x1080)' },
    @{ Group='화면'; Key='max-fps';        Label='최대 프레임';   Type='editcombo'; Default='120';  Items=@('(기본)','144','120','90','60','30'); Arg='--max-fps={0}'; Hint='높을수록 부드럽지만 데이터·발열 증가' },
    @{ Group='화면'; Key='video-bit-rate'; Label='화질';          Type='editcombo'; Default='8M';   Items=@('(기본)','32M','16M','12M','8M','4M','2M'); Arg='--video-bit-rate={0}'; Hint='높을수록 선명하지만 지연·데이터 증가.  32M=최고 · 8M=기본 · 4M=가볍게' },
    @{ Group='화면'; Key='video-codec';    Label='영상 코덱';     Type='combo'; Default='(기본)'; Items=@('(기본)','h264','h265','av1'); Arg='--video-codec={0}'; Hint='h265가 같은 화질에 데이터가 적음 (기기 지원 필요)' },
    @{ Group='화면'; Key='orientation';    Label='화면 방향';     Type='combo'; Default='(기본)'; Items=@('(기본)','0','90','180','270','flip0','flip90','flip180','flip270'); Arg='--orientation={0}'; Hint='창에 보이는 방향만 회전' },
    @{ Group='화면'; Key='crop';           Label='잘라내기';      Type='text';  Default='';     Arg='--crop={0}';           Hint='폭:높이:x:y   예) 1080:1080:0:420' },
    @{ Group='화면'; Key='new-display';    Label='가로 화면 (16:9)'; Type='editcombo'; Default='(기본)'; Items=@('(기본)','1920x1080','1600x900','2560x1440','1280x720'); Arg='--new-display={0}'; Hint='폰과 별개인 가로 화면을 새로 만들어 띄웁니다. 폰 화면(19.3:9)처럼 길쭉하지 않음.  1920x1080 = 16:9' },

    # ---------------- 창 ----------------
    @{ Group='창';   Key='fullscreen';     Label='전체화면으로 시작'; Type='check'; Default=$false; Arg='--fullscreen';       Hint='실행 후 Ctrl+F 로도 전환 가능' },
    @{ Group='창';   Key='always-on-top';  Label='항상 위에';     Type='check'; Default=$false; Arg='--always-on-top';      Hint='다른 창에 안 가려짐' },
    @{ Group='창';   Key='borderless';     Label='테두리 없애기'; Type='check'; Default=$false; Arg='--window-borderless';  Hint='제목표시줄·테두리 제거' },
    @{ Group='창';   Key='window-title';   Label='창 제목';       Type='text';  Default='';     Arg='--window-title={0}';   Hint='비우면 폰 모델명' },
    @{ Group='창';   Key='window-width';   Label='창 너비';       Type='text';  Default='';     Arg='--window-width={0}';   Hint='픽셀. 비우면 자동' },
    @{ Group='창';   Key='window-height';  Label='창 높이';       Type='text';  Default='';     Arg='--window-height={0}';  Hint='픽셀. 비우면 자동' },

    # ---------------- 전원 ----------------
    @{ Group='전원'; Key='turn-screen-off'; Label='화면 끄고 PC로 사용'; Type='check'; Default=$false; Arg='--turn-screen-off'; Hint='화면만 끄고 PC 제어·활성 상태를 자동 유지합니다. 폰의 물리 전원 버튼을 누르면 화면이 다시 켜집니다.' },
    @{ Group='전원'; Key='stay-awake';      Label='충전 중 활성 유지'; Type='check'; Default=$false; Arg='--stay-awake';        Hint='화면을 켠 채 오래 쓸 때만 사용합니다. 충전 중일 때만 작동' },
    @{ Group='전원'; Key='screen-off-timeout'; Label='화면 자동 꺼짐 시간'; Type='text'; Default='500'; Arg='--screen-off-timeout={0}'; Hint='일반 사용 중 자동으로 화면을 끄는 시간(초). 화면 끄고 PC로 사용 중에는 적용하지 않음' },
    @{ Group='전원'; Key='no-power-on';     Label='시작할 때 안 켜기'; Type='check'; Default=$false; Arg='--no-power-on';   Hint='실행해도 폰 화면을 깨우지 않음' },
    @{ Group='전원'; Key='power-off-on-close'; Label='닫을 때 폰 화면 끄기'; Type='check'; Default=$false; Arg='--power-off-on-close'; Hint='창을 닫으면 폰도 화면 꺼짐' },
    @{ Group='전원'; Key='disable-screensaver'; Label='PC 화면보호기 끄기'; Type='check'; Default=$false; Arg='--disable-screensaver'; Hint='보는 동안 PC가 안 잠김' },

    # ---------------- 입력 ----------------
    @{ Group='입력'; Key='keyboard';       Label='키보드 방식';   Type='combo'; Default='uhid';   Items=@('(기본)','uhid','aoa','sdk','disabled'); Arg='--keyboard={0}'; Hint='uhid = 한글 입력 됨.  한/영 전환은 입력칸에 커서를 놓고 Shift+Space.  폰 기본 키보드가 삼성 키보드여야 함' },
    @{ Group='입력'; Key='mouse';          Label='마우스 방식';   Type='combo'; Default='(기본)'; Items=@('(기본)','uhid','aoa','sdk','disabled'); Arg='--mouse={0}';    Hint='uhid = 폰에 진짜 마우스 커서가 생김. 캡처되면 Alt 또는 Windows 키를 눌러 빠져나옵니다' },
    @{ Group='입력'; Key='show-touches';   Label='터치 지점 표시'; Type='check'; Default=$false; Arg='--show-touches';      Hint='어디를 눌렀는지 폰 화면에 동그라미' },
    @{ Group='입력'; Key='prefer-text';    Label='텍스트 입력 우선'; Type='check'; Default=$false; Arg='--prefer-text';     Hint='특수문자 입력이 이상할 때 시도' },
    @{ Group='입력'; Key='no-key-repeat';  Label='키 반복 끄기';  Type='check'; Default=$false; Arg='--no-key-repeat';      Hint='키를 눌러도 반복 입력 안 됨' },
    @{ Group='입력'; Key='no-control';     Label='보기 전용';     Type='check'; Default=$false; Arg='--no-control';         Hint='조작 없이 화면만 보기' },
    # phonepref = scrcpy 옵션이 아니라 '폰 설정'을 직접 바꾸는 토글.
    # 누르는 즉시 adb 로 폰에 반영되고, 명령어 미리보기·프리셋에는 들어가지 않는다.
    @{ Group='입력'; Key='ime-with-hw';    Label='폰 화면 자판 표시'; Type='phonepref'; SettingNs='secure'; SettingKey='show_ime_with_hard_keyboard'; Hint='끄면 PC 키보드로 칠 때 폰 화면 자판이 안 뜹니다.  ※ 폰 설정을 직접 바꿉니다 (즉시 적용)' },

    # ---------------- 소리 ----------------
    @{ Group='소리'; Key='no-audio';       Label='소리 끄기';     Type='check'; Default=$false; Arg='--no-audio';           Hint='폰 소리를 PC로 안 보냄' },
    @{ Group='소리'; Key='audio-codec';    Label='오디오 코덱';   Type='combo'; Default='(기본)'; Items=@('(기본)','opus','aac','flac','raw'); Arg='--audio-codec={0}'; Hint='기본은 opus' },
    @{ Group='소리'; Key='audio-bit-rate'; Label='소리 비트레이트'; Type='text'; Default='';    Arg='--audio-bit-rate={0}'; Hint='예: 128K' },
    @{ Group='소리'; Key='audio-source';   Label='소리 원본';     Type='combo'; Default='(기본)'; Items=@('(기본)','output','playback','mic'); Arg='--audio-source={0}'; Hint='mic = 폰 마이크를 PC로' },
    @{ Group='소리'; Key='audio-dup';      Label='폰에서도 같이 재생'; Type='check'; Default=$false; Arg='--audio-dup';     Hint='기본은 PC로만 나오고 폰은 무음' },

    # ---------------- 녹화 ----------------
    @{ Group='녹화'; Key='record';         Label='녹화 파일';     Type='text';  Default='';     Arg='--record={0}';        Hint='예: C:\rec\phone.mp4   (비우면 녹화 안 함)' },
    @{ Group='녹화'; Key='record-format';  Label='녹화 형식';     Type='combo'; Default='(기본)'; Items=@('(기본)','mp4','mkv','m4a','mka','opus','aac','flac','wav'); Arg='--record-format={0}'; Hint='보통 파일 확장자로 자동 결정' },
    @{ Group='녹화'; Key='time-limit';     Label='자동 종료';     Type='text';  Default='';     Arg='--time-limit={0}';    Hint='초 단위. 예) 600 = 10분 뒤 종료' },
    @{ Group='녹화'; Key='no-video-playback'; Label='영상 표시 안 함'; Type='check'; Default=$false; Arg='--no-video-playback'; Hint='녹화만 할 때 (창 안 뜸)' },

    # ---------------- 기타 ----------------
    @{ Group='기타'; Key='start-app';      Label='시작할 앱';     Type='text';  Default='';     Arg='--start-app={0}';     Hint='패키지명 또는 ?이름   예) ?카카오' },
    @{ Group='기타'; Key='display-id';     Label='화면 번호';     Type='text';  Default='';     Arg='--display-id={0}';    Hint='여러 디스플레이가 있을 때' },
    @{ Group='기타'; Key='render-driver';  Label='렌더러';        Type='combo'; Default='(기본)'; Items=@('(기본)','direct3d11','direct3d','opengl','opengles2','software'); Arg='--render-driver={0}'; Hint='화면이 깨질 때 바꿔보세요' },

    # ---------------- 설정 (PC 마다 다른 값) ----------------
    # path = 실행 파일 위치. 자동으로 못 찾았을 때만 손대면 된다. config.json 에 저장된다.
    @{ Group='설정'; Key='scrcpyPath';     Label='scrcpy.exe 위치'; Type='path'; Hint='여러 버전이 깔려 있으면 가장 높은 버전을 자동으로 고릅니다. 직접 정하려면 [찾아보기]' },
    @{ Group='설정'; Key='adbPath';        Label='adb.exe 위치';    Type='path'; Hint='scrcpy 폴더 안에 같이 들어있는 경우가 많습니다' }
)

# =============================================================
#  아래부터는 화면 만드는 부분 — 옵션만 바꿀 거면 손댈 필요 없음
# =============================================================

# 이 스크립트를 띄운 검은 콘솔 창만 숨긴다 (GUI 창은 그대로 보임).
# ※ 런처에서 pwsh -WindowStyle Hidden 을 쓰면 GUI 창까지 같이 숨겨진다(실측). 그래서 여기서 처리한다.
$ConsoleWin = Add-Type -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -Name 'ConsoleWin' -Namespace 'Native' -PassThru
$null = $ConsoleWin::ShowWindow($ConsoleWin::GetConsoleWindow(), 0)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$xamlDoc = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="scrcpy" Height="814" Width="1000"
        WindowStartupLocation="CenterScreen"
        Background="#1B1B1F" FontFamily="Segoe UI, 맑은 고딕" FontSize="13"
        TextOptions.TextFormattingMode="Display">

  <Window.Resources>

    <!-- 스크롤바 : 얇은 다크 -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border Background="#43434B" CornerRadius="5" Margin="2,0"/>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                </Track.IncreaseRepeatButton>
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                </Track.DecreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 입력칸  ※ Height 고정 = 옆 설명글이 길어져도 박스가 늘어나지 않게 -->
    <Style x:Key="DarkText" TargetType="TextBox">
      <Setter Property="Height" Value="34"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Background" Value="#26262C"/>
      <Setter Property="Foreground" Value="#E9E9EC"/>
      <Setter Property="BorderBrush" Value="#3A3A42"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,0"/>
      <Setter Property="CaretBrush" Value="#E9E9EC"/>
      <Setter Property="SelectionBrush" Value="#2C6BD6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#4C4C57"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#3D82F0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 명령어 미리보기 -->
    <Style x:Key="CmdBox" TargetType="TextBox" BasedOn="{StaticResource DarkText}">
      <Setter Property="Background" Value="#141418"/>
      <Setter Property="Foreground" Value="#8FD9A8"/>
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="IsReadOnly" Value="True"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="BorderBrush" Value="#2C2C34"/>
      <Setter Property="Height" Value="Auto"/>
      <Setter Property="VerticalAlignment" Value="Stretch"/>
      <Setter Property="VerticalContentAlignment" Value="Top"/>
      <Setter Property="Padding" Value="11,9"/>
    </Style>

    <!-- 선택목록 -->
    <Style x:Key="ComboItem" TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#D8D8DE"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}" CornerRadius="4" Margin="3,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#33333C"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#2C4E86"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="DarkCombo" TargetType="ComboBox">
      <Setter Property="Height" Value="34"/>
      <Setter Property="Foreground" Value="#E9E9EC"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource ComboItem}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="Tgl" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Bd" Background="#26262C" BorderBrush="#3A3A42" BorderThickness="1" CornerRadius="7">
                      <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0"
                            Data="M 0 0 L 5 5 L 10 0" Stroke="#9A9AA4" StrokeThickness="1.5"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Bd" Property="BorderBrush" Value="#4C4C57"/>
                      </Trigger>
                      <Trigger Property="IsChecked" Value="True">
                        <Setter TargetName="Bd" Property="BorderBrush" Value="#3D82F0"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}"
                                Margin="12,0,32,0" VerticalAlignment="Center"
                                TextBlock.Foreground="#E9E9EC"/>
              <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True"
                     Focusable="False" PopupAnimation="Fade">
                <Border Background="#26262C" BorderBrush="#3A3A42" BorderThickness="1" CornerRadius="7"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                        Margin="0,4,0,0" Padding="0,4">
                  <ScrollViewer MaxHeight="280">
                    <StackPanel IsItemsHost="True"/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 선택목록 + 직접입력 (해상도·프레임·화질처럼 자주 쓰는 값이 있는 항목) -->
    <Style x:Key="EditCombo" TargetType="ComboBox">
      <Setter Property="Height" Value="34"/>
      <Setter Property="IsEditable" Value="True"/>
      <Setter Property="Foreground" Value="#E9E9EC"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource ComboItem}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <Border x:Name="Bd" Background="#26262C" BorderBrush="#3A3A42" BorderThickness="1" CornerRadius="7"/>
              <TextBox x:Name="PART_EditableTextBox" Background="Transparent" BorderThickness="0"
                       Foreground="#E9E9EC" CaretBrush="#E9E9EC" SelectionBrush="#2C6BD6"
                       Margin="11,0,34,0" VerticalAlignment="Center" VerticalContentAlignment="Center"/>
              <ToggleButton x:Name="Tgl" Width="32" HorizontalAlignment="Right" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border Background="Transparent">
                      <Path HorizontalAlignment="Center" VerticalAlignment="Center"
                            Data="M 0 0 L 5 5 L 10 0" Stroke="#9A9AA4" StrokeThickness="1.5"/>
                    </Border>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True"
                     Focusable="False" PopupAnimation="Fade">
                <Border Background="#26262C" BorderBrush="#3A3A42" BorderThickness="1" CornerRadius="7"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                        Margin="0,4,0,0" Padding="0,4">
                  <ScrollViewer MaxHeight="280">
                    <StackPanel IsItemsHost="True"/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#4C4C57"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocusWithin" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#3D82F0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 토글 스위치 -->
    <Style x:Key="Toggle" TargetType="CheckBox">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border Background="Transparent" Padding="0,2">
              <Border x:Name="Track" Width="46" Height="26" CornerRadius="13"
                      Background="#3A3A42" HorizontalAlignment="Left">
                <Ellipse x:Name="Knob" Width="20" Height="20" Fill="#9A9AA4"
                         HorizontalAlignment="Left" Margin="3,0,0,0"/>
              </Border>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="#2F72E0"/>
                <Setter TargetName="Knob" Property="Fill" Value="#FFFFFF"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,3,0"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Track" Property="Opacity" Value="0.85"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 버튼 : 파란 강조 -->
    <Style x:Key="Accent" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="20,10"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="#2F72E0" CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#4183EC"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#255FC0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 버튼 : 보조 -->
    <Style x:Key="Ghost" TargetType="Button">
      <Setter Property="Foreground" Value="#D8D8DE"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="#26262C" BorderBrush="#3A3A42" BorderThickness="1"
                    CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#31313A"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#4C4C57"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1F1F25"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 왼쪽 메뉴 -->
    <Style x:Key="NavItem" TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#A8A8B2"/>
      <Setter Property="FontSize" Value="13.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" Background="Transparent" BorderBrush="Transparent"
                    BorderThickness="3,0,0,0" Padding="19,11,16,11">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#26262C"/>
                <Setter Property="Foreground" Value="#E9E9EC"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#2A2A32"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#3D82F0"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="56"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- ===== 헤더 ===== -->
    <Border Grid.Row="0" Background="#202026" BorderBrush="#2E2E36" BorderThickness="0,0,0,1">
      <Grid Margin="22,0">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="scrcpy" FontSize="19" FontWeight="SemiBold" Foreground="#F0F0F3"/>
          <TextBlock Text="설정" FontSize="19" Foreground="#6E6E7A" Margin="9,0,0,0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <Ellipse x:Name="DevDot" Width="9" Height="9" Fill="#4A4A52" Margin="0,0,9,0"/>
          <Button x:Name="BtnPair" Content="무선 페어링" Style="{StaticResource Ghost}" Margin="0,0,9,0"/>
          <ComboBox x:Name="CmbDevice" Width="230" Style="{StaticResource DarkCombo}"/>
          <Button x:Name="BtnRefresh" Content="새로고침" Style="{StaticResource Ghost}" Margin="9,0,0,0"/>
          <Button x:Name="BtnDiscover" Content="기기 찾기" Style="{StaticResource Ghost}" Margin="6,0,0,0"
                  ToolTip="폰을 같은 Wi-Fi 에서 찾아 자동으로 연결합니다 (케이블·폰 조작 불필요)"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ===== 본문 ===== -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="176"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="#202026" BorderBrush="#2E2E36" BorderThickness="0,0,1,0">
        <ListBox x:Name="NavList" Background="Transparent" BorderThickness="0" Margin="0,12,0,0"
                 ItemContainerStyle="{StaticResource NavItem}"
                 ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
      </Border>

      <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto" Padding="0,0,6,0">
        <StackPanel x:Name="OptionHost" Margin="30,24,24,28"/>
      </ScrollViewer>
    </Grid>

    <!-- ===== 하단 ===== -->
    <Border Grid.Row="2" Background="#202026" BorderBrush="#2E2E36" BorderThickness="0,1,0,0" Padding="22,16,22,18">
      <StackPanel>

        <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
          <TextBlock Text="프리셋" Foreground="#8A8A94" VerticalAlignment="Center" Margin="0,0,10,0"/>
          <ComboBox x:Name="CmbPreset" Width="190" Style="{StaticResource DarkCombo}"/>
          <TextBox x:Name="TxtPresetName" Width="150" Style="{StaticResource DarkText}" Margin="8,0,0,0"
                   ToolTip="새 이름을 적고 저장을 누르면 새 프리셋이 됩니다"/>
          <Button x:Name="BtnPresetSave" Content="저장" Style="{StaticResource Ghost}" Margin="8,0,0,0"/>
          <Button x:Name="BtnPresetDel"  Content="삭제" Style="{StaticResource Ghost}" Margin="6,0,0,0"/>
          <TextBlock Text="직접 추가" Foreground="#8A8A94" VerticalAlignment="Center" Margin="22,0,10,0"/>
          <TextBox x:Name="TxtExtra" Width="230" Style="{StaticResource DarkText}" FontFamily="Consolas"/>
        </StackPanel>

        <TextBox x:Name="TxtCmd" Style="{StaticResource CmdBox}" Height="58" Margin="0,0,0,14"/>

        <StackPanel Orientation="Horizontal">
          <Button x:Name="BtnRun"  Content="실행"        Style="{StaticResource Accent}" Width="150"/>
          <Button x:Name="BtnCopy" Content="명령어 복사"  Style="{StaticResource Ghost}"  Margin="10,0,0,0"/>
          <Button x:Name="BtnBat"  Content=".bat 로 저장" Style="{StaticResource Ghost}"  Margin="8,0,0,0"/>
          <TextBlock x:Name="LblStatus" Foreground="#7E7E88" VerticalAlignment="Center" Margin="20,0,0,0"/>
        </StackPanel>

      </StackPanel>
    </Border>

  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xamlDoc
$win = [Windows.Markup.XamlReader]::Load($reader)

# 이름 있는 요소 꺼내기
$NavList       = $win.FindName('NavList')
$OptionHost    = $win.FindName('OptionHost')
$CmbDevice     = $win.FindName('CmbDevice')
$DevDot        = $win.FindName('DevDot')
$BtnPair       = $win.FindName('BtnPair')
$BtnRefresh    = $win.FindName('BtnRefresh')
$BtnDiscover   = $win.FindName('BtnDiscover')
$CmbPreset     = $win.FindName('CmbPreset')
$TxtPresetName = $win.FindName('TxtPresetName')
$BtnPresetSave = $win.FindName('BtnPresetSave')
$BtnPresetDel  = $win.FindName('BtnPresetDel')
$TxtExtra      = $win.FindName('TxtExtra')
$TxtCmd        = $win.FindName('TxtCmd')
$BtnRun        = $win.FindName('BtnRun')
$BtnCopy       = $win.FindName('BtnCopy')
$BtnBat        = $win.FindName('BtnBat')
$LblStatus     = $win.FindName('LblStatus')

$Controls = @{}
$Pages    = @{}
$script:Presets = @{}
$script:ready   = $false
$script:powerOptionsUpdating = $false
$script:stayAwakeBeforeScreenOff = $null
$script:noControlBeforeScreenOff = $null
# 기기 콤보는 사람이 읽을 라벨을 보여주고, scrcpy 에는 진짜 기기 ID 를 넘긴다.
$script:DeviceIdByLabel = @{}
$script:OfflineLabels   = [System.Collections.Generic.HashSet[string]]::new()

$StyleText  = $win.FindResource('DarkText')
$StyleCombo = $win.FindResource('DarkCombo')
$StyleEdit  = $win.FindResource('EditCombo')
$StyleToggle= $win.FindResource('Toggle')

$ColLabel = [Windows.Media.BrushConverter]::new().ConvertFromString('#E4E4E9')
$ColHint  = [Windows.Media.BrushConverter]::new().ConvertFromString('#76767F')
$ColTitle = [Windows.Media.BrushConverter]::new().ConvertFromString('#F0F0F3')
$ColGreen = [Windows.Media.BrushConverter]::new().ConvertFromString('#3FB950')
$ColGray  = [Windows.Media.BrushConverter]::new().ConvertFromString('#4A4A52')

# ---------- 그룹별 페이지 생성 ----------
foreach ($group in ($OPTIONS.Group | Select-Object -Unique)) {

    $panel = New-Object Windows.Controls.StackPanel

    $title = New-Object Windows.Controls.TextBlock
    $title.Text = $group
    $title.FontSize = 20
    $title.FontWeight = 'SemiBold'
    $title.Foreground = $ColTitle
    $title.Margin = '0,0,0,22'
    [void]$panel.Children.Add($title)

    foreach ($opt in ($OPTIONS | Where-Object { $_.Group -eq $group })) {

        $row = New-Object Windows.Controls.StackPanel
        $row.Margin = '0,0,0,20'

        $lbl = New-Object Windows.Controls.TextBlock
        $lbl.Text = $opt.Label
        $lbl.Foreground = $ColLabel
        $lbl.FontSize = 13.5
        $lbl.Margin = '0,0,0,7'
        [void]$row.Children.Add($lbl)

        $line = New-Object Windows.Controls.StackPanel
        $line.Orientation = 'Horizontal'

        $extraCtrl = $null   # 일부 항목은 컨트롤 옆에 버튼이 하나 더 붙는다 (예: 경로 [찾아보기])

        switch ($opt.Type) {
            'check' {
                $c = New-Object Windows.Controls.CheckBox
                $c.Style = $StyleToggle
                $c.IsChecked = [bool]$opt.Default
                $c.VerticalAlignment = 'Center'
                $c.Add_Checked({ Update-Preview })
                $c.Add_Unchecked({ Update-Preview })
            }
            'path' {
                # 실행 파일 경로 지정칸 + [찾아보기]. 고르면 config.json 에 바로 저장된다.
                # (다음 실행부터 적용 — 지금 떠 있는 세션의 $SCRCPY_EXE 를 바꾸지는 않는다)
                $c = New-Object Windows.Controls.TextBox
                $c.Style = $StyleText
                $c.Width = 330
                $c.Text = [string]$(if ($opt.Key -eq 'scrcpyPath') { $SCRCPY_EXE } else { $ADB_EXE })
                $c.Tag = $opt
                $c.Add_TextChanged({
                    param($s, $e)
                    $script:Config[$s.Tag.Key] = $s.Text.Trim()
                    $null = Write-Config $script:Config
                })

                $extraCtrl = New-Object Windows.Controls.Button
                $extraCtrl.Content = '찾아보기'
                $extraCtrl.Style = $win.FindResource('Ghost')
                $extraCtrl.Margin = '8,0,0,0'
                $extraCtrl.Tag = $c
                $extraCtrl.Add_Click({
                    param($s, $e)
                    $box = $s.Tag
                    $dlg = New-Object Microsoft.Win32.OpenFileDialog
                    $dlg.Filter = '실행 파일 (*.exe)|*.exe'
                    if ($box.Text -and (Test-Path $box.Text)) {
                        $dlg.FileName = Split-Path $box.Text -Leaf
                        $dlg.InitialDirectory = Split-Path $box.Text -Parent
                    }
                    if ($dlg.ShowDialog()) {
                        $box.Text = $dlg.FileName
                        $LblStatus.Text = '저장했습니다. 다음 실행부터 적용됩니다.'
                    }
                })
            }
            'phonepref' {
                # 폰 설정을 직접 바꾸는 토글. 현재 값은 시작할 때 폰에서 읽어온다.
                # Add_Click 을 쓰는 이유: Checked/Unchecked 는 코드로 값을 넣을 때도 발동해서
                # 초기화 중에 폰 설정을 덮어써 버린다. Click 은 사람이 누를 때만 발동.
                $c = New-Object Windows.Controls.CheckBox
                $c.Style = $StyleToggle
                $c.VerticalAlignment = 'Center'
                $c.Tag = $opt
                $c.Add_Click({
                    param($s, $e)
                    $o = $s.Tag
                    $v = if ($s.IsChecked) { '1' } else { '0' }
                    $approved = [Windows.MessageBox]::Show(
                        "휴대폰 설정을 직접 바꿉니다.`n`n$($o.Label): " + $(if ($s.IsChecked) { '켬' } else { '끔' }) +
                        "`n되돌리기: 이 토글을 다시 반대로 바꾸세요.`n`n계속할까요?",
                        '휴대폰 설정 변경 확인', 'YesNo', 'Warning')
                    if ($approved -ne [Windows.MessageBoxResult]::Yes) {
                        $s.IsChecked = -not [bool]$s.IsChecked
                        return
                    }
                    try {
                        & $ADB_EXE shell settings put $o.SettingNs $o.SettingKey $v 2>$null | Out-Null
                        $LblStatus.Text = "폰 설정 반영: $($o.Label) = " + $(if ($s.IsChecked) { '켬' } else { '끔' })
                    } catch {
                        $LblStatus.Text = "폰 설정 변경 실패 — 기기 연결을 확인하세요"
                    }
                })
            }
            'combo' {
                $c = New-Object Windows.Controls.ComboBox
                $c.Style = $StyleCombo
                $c.Width = 210
                foreach ($i in $opt.Items) { [void]$c.Items.Add($i) }
                $c.SelectedItem = $opt.Default
                $c.Add_SelectionChanged({ Update-Preview })
            }
            'editcombo' {
                # 목록에서 고를 수도, 직접 칠 수도 있는 칸.
                # ※ 여기서 편집칸 Text 를 코드로 다시 쓰면 안 된다 — WPF 는 선택 처리 도중 Text 를
                #   건드리면 선택이 풀리면서 칸이 비어버린다(실측). 그래서 목록 항목은 값 그대로만 넣는다.
                $c = New-Object Windows.Controls.ComboBox
                $c.Style = $StyleEdit
                $c.Width = 210
                foreach ($i in $opt.Items) { [void]$c.Items.Add($i) }
                $c.Text = [string]$opt.Default
                $c.Add_SelectionChanged({ Update-Preview })
                $c.Add_KeyUp({ Update-Preview })
            }
            default {
                $c = New-Object Windows.Controls.TextBox
                $c.Style = $StyleText
                $c.Width = 210
                $c.Text = [string]$opt.Default
                $c.Add_TextChanged({ Update-Preview })
            }
        }
        [void]$line.Children.Add($c)
        if ($extraCtrl) { [void]$line.Children.Add($extraCtrl) }

        $hint = New-Object Windows.Controls.TextBlock
        $hint.Text = $opt.Hint
        $hint.Foreground = $ColHint
        $hint.FontSize = 12
        $hint.VerticalAlignment = 'Center'
        $hint.Margin = '14,0,0,0'
        $hint.TextWrapping = 'Wrap'
        $hint.MaxWidth = 380
        [void]$line.Children.Add($hint)

        [void]$row.Children.Add($line)
        [void]$panel.Children.Add($row)

        $Controls[$opt.Key] = $c
    }

    if ($group -eq '설정') {
        $install = New-Object Windows.Controls.StackPanel
        $install.Margin = '0,10,0,0'

        $installTitle = New-Object Windows.Controls.TextBlock
        $installTitle.Text = '공식 scrcpy 설치'
        $installTitle.Foreground = $ColLabel
        $installTitle.FontSize = 13.5
        $installTitle.Margin = '0,0,0,7'
        [void]$install.Children.Add($installTitle)

        $installRootLabel = New-Object Windows.Controls.TextBlock
        $installRootLabel.Text = '설치 폴더 (선택한 폴더 아래에 버전별 폴더를 만듭니다)'
        $installRootLabel.Foreground = $ColHint
        $installRootLabel.FontSize = 12
        $installRootLabel.Margin = '0,0,0,7'
        [void]$install.Children.Add($installRootLabel)

        $installRootLine = New-Object Windows.Controls.StackPanel
        $installRootLine.Orientation = 'Horizontal'

        $installRootBox = New-Object Windows.Controls.TextBox
        $installRootBox.Style = $StyleText
        $installRootBox.Width = 330
        $installRootBox.Text = [string]$(if ($script:Config.ContainsKey('installRoot') -and $script:Config.installRoot) { $script:Config.installRoot } else { $DEFAULT_SCRCPY_INSTALL_ROOT })
        $installRootBox.Add_TextChanged({
            param($s, $e)
            $script:Config['installRoot'] = $s.Text.Trim()
            $null = Write-Config $script:Config
        })
        $script:InstallRootBox = $installRootBox
        [void]$installRootLine.Children.Add($installRootBox)

        $installRootBrowse = New-Object Windows.Controls.Button
        $installRootBrowse.Content = '설치 폴더 선택'
        $installRootBrowse.Style = $win.FindResource('Ghost')
        $installRootBrowse.Margin = '8,0,0,0'
        $installRootBrowse.Tag = $installRootBox
        $installRootBrowse.Add_Click({
            param($s, $e)
            Add-Type -AssemblyName System.Windows.Forms
            $box = $s.Tag
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'scrcpy 버전별 설치 폴더를 만들 위치를 고르세요.'
            if ($box.Text -and (Test-Path -LiteralPath $box.Text)) { $dlg.SelectedPath = $box.Text }
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $box.Text = $dlg.SelectedPath }
        })
        [void]$installRootLine.Children.Add($installRootBrowse)

        [void]$install.Children.Add($installRootLine)

        $installLine = New-Object Windows.Controls.StackPanel
        $installLine.Orientation = 'Horizontal'

        $installButton = New-Object Windows.Controls.Button
        $installButton.Content = '공식 최신 버전 설치'
        $installButton.Style = $win.FindResource('Ghost')
        $installButton.Add_Click({ Install-OfficialScrcpy })
        [void]$installLine.Children.Add($installButton)

        $guideButton = New-Object Windows.Controls.Button
        $guideButton.Content = '설치 안내 열기'
        $guideButton.Style = $win.FindResource('Ghost')
        $guideButton.Margin = '8,0,0,0'
        $guideButton.Add_Click({
            $guidePath = Join-Path $PSScriptRoot 'scrcpy-install-guide.html'
            if (-not (Test-Path -LiteralPath $guidePath)) {
                [void][Windows.MessageBox]::Show(
                    "설치 안내 파일을 찾지 못했습니다.`n`n경로: $guidePath",
                    'scrcpy 설치 안내', 'OK', 'Error')
                return
            }
            try {
                # 사용자가 직접 누른 버튼으로만 기본 브라우저를 열며, 설치·다운로드는 시작하지 않는다.
                Start-Process -FilePath $guidePath -ErrorAction Stop
            } catch {
                [void][Windows.MessageBox]::Show(
                    "설치 안내를 열지 못했습니다.`n`n$($_.Exception.Message)",
                    'scrcpy 설치 안내', 'OK', 'Error')
            }
        })
        [void]$installLine.Children.Add($guideButton)

        $installHint = New-Object Windows.Controls.TextBlock
        $installHint.Text = 'Genymobile GitHub 릴리스만 사용합니다. 다운로드 전에 버전·출처·SHA-256 검증·설치 경로를 확인합니다.'
        $installHint.Foreground = $ColHint
        $installHint.FontSize = 12
        $installHint.VerticalAlignment = 'Center'
        $installHint.Margin = '14,0,0,0'
        $installHint.TextWrapping = 'Wrap'
        $installHint.MaxWidth = 380
        [void]$installLine.Children.Add($installHint)

        [void]$install.Children.Add($installLine)
        [void]$panel.Children.Add($install)
    }

    $Pages[$group] = $panel
    [void]$NavList.Items.Add($group)
}

# =============================================================
#  기능
# =============================================================

function Get-ScrcpyArgs {
    $list = [System.Collections.Generic.List[string]]::new()
    $screenOffMode = [bool]$Controls['turn-screen-off'].IsChecked

    $deviceLabel = [string]$CmbDevice.SelectedItem
    if ($deviceLabel -and $deviceLabel -ne '(자동)' -and $script:DeviceIdByLabel.ContainsKey($deviceLabel)) {
        $list.Add('--serial=' + $script:DeviceIdByLabel[$deviceLabel])
    }
    foreach ($opt in $OPTIONS) {
        # 화면을 직접 끄는 모드에서는 이 둘이 의미가 없다. 충전 여부나 시간을
        # 사용자가 조합해서 기억하지 않아도 되도록, 단일 모드가 활성 유지를 맡는다.
        if ($screenOffMode -and $opt.Key -in @('stay-awake', 'screen-off-timeout')) { continue }
        $c = $Controls[$opt.Key]
        switch ($opt.Type) {
            'phonepref' { }   # 폰 설정이라 scrcpy 명령어에는 안 들어감
            'path'      { }   # 실행 파일 위치라 scrcpy 명령어에는 안 들어감
            'check'     {
                if ($c.IsChecked) {
                    $list.Add($opt.Arg)
                    if ($opt.Key -eq 'turn-screen-off') { $list.Add('--keep-active') }
                }
            }
            'combo'     { $v = [string]$c.SelectedItem; if ($v -and $v -ne '(기본)') { $list.Add($opt.Arg -f $v) } }
            'editcombo' {
                # 목록에서 고른 직후엔 '1920  FHD…' 형태일 수 있으므로 값(첫 토막)만 쓴다
                $v = (([string]$c.Text -split '\s{2,}')[0]).Trim()
                if ($v -and $v -ne '(기본)') { $list.Add($opt.Arg -f $v) }
            }
            default     { $v = $c.Text.Trim();          if ($v)                     { $list.Add($opt.Arg -f $v) } }
        }
    }
    $extra = $TxtExtra.Text.Trim()
    if ($extra) { foreach ($e in ($extra -split '\s+')) { $list.Add($e) } }
    return $list.ToArray()
}

function Format-Cmd {
    param([string[]]$Arguments)
    $quoted = $Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    return 'scrcpy ' + ($quoted -join ' ')
}

function Update-Preview {
    if (-not $script:ready) { return }
    $TxtCmd.Text = Format-Cmd (Get-ScrcpyArgs)
}

# '화면 끄고 PC로 사용'은 화면만 끄고 기기를 깨운 상태로 유지하는 하나의 작업이다.
# 하위 옵션을 같이 켜게 두면 충전 여부나 적용 순서를 사용자가 외워야 하므로,
# 이 모드에서는 중복·무의미한 옵션을 비활성화한다. 기존 선택은 모드를 끄면 복원한다.
function Update-PowerOptionState {
    if ($script:powerOptionsUpdating -or -not $Controls.ContainsKey('turn-screen-off')) { return }

    $script:powerOptionsUpdating = $true
    try {
        $screenOffMode = [bool]$Controls['turn-screen-off'].IsChecked
        $stayAwake = $Controls['stay-awake']
        $timeout = $Controls['screen-off-timeout']
        $noControl = $Controls['no-control']

        if ($screenOffMode) {
            if ($null -eq $script:stayAwakeBeforeScreenOff) {
                $script:stayAwakeBeforeScreenOff = [bool]$stayAwake.IsChecked
            }
            $stayAwake.IsChecked = $false
            $stayAwake.IsEnabled = $false
            $stayAwake.Opacity = 0.45
            $stayAwake.ToolTip = '화면 끄고 PC로 사용이 활성 상태에서는 활성 유지가 자동으로 적용됩니다.'

            $timeout.IsEnabled = $false
            $timeout.Opacity = 0.45
            $timeout.ToolTip = '화면 끄고 PC로 사용은 즉시 화면을 끄므로 자동 꺼짐 시간을 사용하지 않습니다.'

            if ($null -eq $script:noControlBeforeScreenOff) {
                $script:noControlBeforeScreenOff = [bool]$noControl.IsChecked
            }
            $noControl.IsChecked = $false
            $noControl.IsEnabled = $false
            $noControl.Opacity = 0.45
            $noControl.ToolTip = '화면 끄고 PC로 사용은 PC 제어가 필요하므로 보기 전용을 함께 사용할 수 없습니다.'
        } else {
            $stayAwake.IsEnabled = $true
            $stayAwake.Opacity = 1
            $stayAwake.ToolTip = $null
            if ($null -ne $script:stayAwakeBeforeScreenOff) {
                $stayAwake.IsChecked = $script:stayAwakeBeforeScreenOff
                $script:stayAwakeBeforeScreenOff = $null
            }

            $timeout.IsEnabled = $true
            $timeout.Opacity = 1
            $timeout.ToolTip = $null

            $noControl.IsEnabled = $true
            $noControl.Opacity = 1
            $noControl.ToolTip = $null
            if ($null -ne $script:noControlBeforeScreenOff) {
                $noControl.IsChecked = $script:noControlBeforeScreenOff
                $script:noControlBeforeScreenOff = $null
            }
        }
    } finally {
        $script:powerOptionsUpdating = $false
    }
}

# 직접 추가 인자는 고급 기능이지만, 화면을 끄는 동시에 제어를 끄는 조합은
# scrcpy가 즉시 오류로 종료한다. 이 경우에는 실행·배치 파일 생성을 막고 이유를 알린다.
function Get-ScrcpyOptionConflicts {
    $extraArgs = @($TxtExtra.Text.Trim() -split '\s+' | Where-Object { $_ })
    $shortFlags = @($extraArgs | Where-Object { $_ -match '^-[^-]+$' })
    $screenOffRequested = [bool]$Controls['turn-screen-off'].IsChecked -or
        [bool]($extraArgs | Where-Object { $_ -eq '--turn-screen-off' }) -or
        [bool]($shortFlags | Where-Object { $_ -cmatch 'S' })
    $noControlRequested = [bool]$Controls['no-control'].IsChecked -or
        [bool]($extraArgs | Where-Object { $_ -eq '--no-control' }) -or
        [bool]($shortFlags | Where-Object { $_ -cmatch 'n' })

    if ($screenOffRequested -and $noControlRequested) {
        return @('화면 끄고 PC로 사용과 보기 전용은 함께 쓸 수 없습니다. 보기 전용을 끄거나 직접 추가 인자에서 --no-control(-n)을 지우세요.')
    }
    return @()
}

# adb devices -l 한 줄 = 기기 하나. 헤더('List of devices attached')와 데몬 메시지가 섞여 나오므로
# 두 번째 낱말이 실제 상태값일 때만 기기로 인정한다.
function Get-AdbDevices {
    $list = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($line in (& $ADB_EXE devices -l 2>$null)) {
            if ([string]$line -notmatch '^(?<id>\S+)\s+(?<state>device|offline|unauthorized|authorizing|connecting|recovery|sideload|bootloader)\b') { continue }
            $id = $Matches['id']; $state = $Matches['state']
            $model = if ([string]$line -match '\smodel:(\S+)') { $Matches[1] } else { '' }
            $list.Add([pscustomobject]@{ Id = $id; State = $state; Model = $model })
        }
    } catch { }
    return $list
}

# 기기 목록은 '지금 붙어 있는 것'과 '전에 붙었던 것'을 함께 보여준다.
# 과거 기기를 지우지 않는 이유: 목록에서 사라지면 재연결할 대상을 고를 수조차 없다.
# (이 폰은 mDNS 이름으로 잡혀서 그 이름으로 adb connect 가 안 된다 — 재연결은 [기기 찾기]가 맡는다)
function Refresh-Devices {
    $sel = [string]$CmbDevice.SelectedItem
    $found = Get-AdbDevices
    $online = @($found | Where-Object { $_.State -eq 'device' })

    # 붙어 있는 기기를 config 에 적어둔다 → 다음에 꺼져 있어도 목록에 남는다
    $known = @{}
    if ($script:Config.ContainsKey('devices') -and $script:Config['devices']) {
        foreach ($k in $script:Config['devices'].Keys) { $known[$k] = $script:Config['devices'][$k] }
    }
    foreach ($d in $online) {
        $known[$d.Id] = @{ model = $d.Model; lastSeen = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    }
    if ($known.Count) {
        $script:Config['devices'] = $known
        $null = Write-Config $script:Config
    }

    $script:DeviceIdByLabel = @{}
    $script:OfflineLabels = [System.Collections.Generic.HashSet[string]]::new()
    $CmbDevice.Items.Clear()
    [void]$CmbDevice.Items.Add('(자동)')

    foreach ($d in $online) {
        $label = if ($d.Model) { "$($d.Model)  ·  $($d.Id)" } else { $d.Id }
        $script:DeviceIdByLabel[$label] = $d.Id
        [void]$CmbDevice.Items.Add($label)
    }

    $onlineIds = @($online | ForEach-Object { $_.Id })
    foreach ($id in ($known.Keys | Sort-Object)) {
        if ($onlineIds -contains $id) { continue }
        $model = [string]$known[$id]['model']
        $label = if ($model) { "(오프라인) $model  ·  $id" } else { "(오프라인) $id" }
        $script:DeviceIdByLabel[$label] = $id
        [void]$script:OfflineLabels.Add($label)
        [void]$CmbDevice.Items.Add($label)
    }

    if ($sel -and $CmbDevice.Items.Contains($sel)) { $CmbDevice.SelectedItem = $sel }
    else { $CmbDevice.SelectedIndex = 0 }

    $states = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($d in ($found | Where-Object { $_.State -ne 'device' })) { [void]$states.Add($d.State) }

    if (-not $SCRCPY_EXE) {
        $DevDot.Fill = $ColGray
        $LblStatus.Text = 'scrcpy.exe 를 찾지 못했습니다 — 왼쪽 [설정] 에서 위치를 지정하세요'
    }
    elseif ($online.Count -gt 0) { $DevDot.Fill = $ColGreen; $LblStatus.Text = "기기 $($online.Count) 대 연결됨" }
    elseif ($states.Contains('unauthorized')) { $DevDot.Fill = $ColGray; $LblStatus.Text = '무선 디버깅 허용 대기 — 폰에서 허용한 뒤 [새로고침]을 누르세요' }
    elseif ($states.Contains('offline')) { $DevDot.Fill = $ColGray; $LblStatus.Text = '기기가 offline — [기기 찾기]를 누르거나 폰의 무선 디버깅을 껐다 켜세요' }
    else              { $DevDot.Fill = $ColGray;  $LblStatus.Text = '연결된 기기 없음 — [기기 찾기]를 눌러보세요' }
}

# 상태줄을 바꾼 뒤 화면에 실제로 그려지게 한다. (찾기 과정이 몇 초 걸려서 단계가 보여야 한다)
function Update-Ui {
    param([string]$Text)
    if ($Text) { $LblStatus.Text = $Text }
    $win.Dispatcher.Invoke([action] {}, [Windows.Threading.DispatcherPriority]::Background)
}

function Wait-Ui {
    param([int]$Milliseconds)
    $end = (Get-Date).AddMilliseconds($Milliseconds)
    while ((Get-Date) -lt $end) {
        $win.Dispatcher.Invoke([action] {}, [Windows.Threading.DispatcherPriority]::Background)
        Start-Sleep -Milliseconds 50
    }
}

# 포트가 열려 있는지만 본다. adb connect 는 안 열린 포트에서 몇 초씩 매달리므로 먼저 걸러낸다.
function Test-TcpPort {
    param([string]$IpAddress, [int]$Port, [int]$TimeoutMs = 1000)
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        if (-not $client.ConnectAsync($IpAddress, $Port).Wait($TimeoutMs)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

# 같은 Wi-Fi 에서 폰을 찾아 붙인다. 폰을 만지지 않고 되는 경로부터 순서대로 시도한다.
#   ① adb devices        — adb 데몬이 mDNS 로 알아서 붙는다 (평소엔 여기서 끝난다)
#   ② adb mdns services  — 데몬이 광고를 주울 때까지 잠깐 기다리며 IP:포트를 모은다
#   ③ TCP probe          — 살아 있는 후보만 남긴다 (죽은 주소로 connect 하면 오래 매달린다)
#   ④ adb connect        — 살아 있는 것에만 붙인다
# ※ 이 폰은 기기 ID 가 mDNS 이름이라 그 이름으로는 connect 가 안 된다(실측). 그래서 ②가 필요하다.
function Find-WirelessDevices {
    if (-not $ADB_EXE) {
        [void][Windows.MessageBox]::Show('adb.exe 를 찾을 수 없습니다. [설정] 에서 지정하거나 [공식 최신 버전 설치]를 누르세요.', '기기 찾기', 'OK', 'Error')
        return
    }

    $BtnDiscover.IsEnabled = $false
    $BtnRefresh.IsEnabled = $false
    try {
        Update-Ui '기기 찾는 중 — 이미 연결돼 있는지 확인합니다…'
        if (@(Get-AdbDevices | Where-Object { $_.State -eq 'device' }).Count -gt 0) {
            Refresh-Devices
            $LblStatus.Text = '이미 연결돼 있습니다 — 바로 [실행] 하세요'
            return
        }

        # 데몬이 mDNS 광고를 줍는 데 시간이 걸린다. 즉시 한 번 보고 없으면 잠깐씩 기다리며 다시 본다.
        $candidates = [System.Collections.Generic.List[string]]::new()
        $deadline = (Get-Date).AddSeconds(8)
        do {
            Update-Ui '기기 찾는 중 — 같은 Wi-Fi 에서 폰을 검색합니다…'
            try {
                foreach ($line in (& $ADB_EXE mdns services 2>$null)) {
                    if ([string]$line -match '(?<ip>\d{1,3}(?:\.\d{1,3}){3}):(?<port>\d{1,5})\s*$') {
                        $endpoint = "$($Matches['ip']):$($Matches['port'])"
                        if (-not $candidates.Contains($endpoint)) { [void]$candidates.Add($endpoint) }
                        $fallback = "$($Matches['ip']):5555"
                        if (-not $candidates.Contains($fallback)) { [void]$candidates.Add($fallback) }
                    }
                }
            } catch { }
            if ($candidates.Count) { break }
            Wait-Ui 700
        } while ((Get-Date) -lt $deadline)

        if (-not $candidates.Count) {
            Refresh-Devices
            $LblStatus.Text = '폰을 찾지 못했습니다 — 폰에서 무선 디버깅을 켜고(퀵설정 타일) 같은 Wi-Fi 인지 확인하세요'
            return
        }

        $connected = 0
        foreach ($endpoint in $candidates) {
            # $host 는 PowerShell 예약 변수라 여기에 대입하면 실행이 깨진다. 다른 이름을 쓴다.
            $hostAddress, $portText = $endpoint -split ':'
            Update-Ui "기기 찾는 중 — $endpoint 응답 확인…"
            if (-not (Test-TcpPort -IpAddress $hostAddress -Port ([int]$portText))) { continue }

            Update-Ui "기기 찾는 중 — $endpoint 에 연결합니다…"
            # ProcessStartInfo.ArgumentList 는 주소를 셸로 재해석하지 않고 adb 에 그대로 넘긴다.
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $ADB_EXE
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.ArgumentList.Add('connect')
            $psi.ArgumentList.Add($endpoint)
            try {
                $proc = [System.Diagnostics.Process]::Start($psi)
                $out = $proc.StandardOutput.ReadToEnd() + $proc.StandardError.ReadToEnd()
                $proc.WaitForExit()
                if ($proc.ExitCode -eq 0 -and $out -notmatch 'cannot|failed|refused') { $connected++ }
            } catch { }
        }

        Refresh-Devices
        if (@(Get-AdbDevices | Where-Object { $_.State -eq 'device' }).Count -gt 0) {
            $LblStatus.Text = '연결됐습니다 — [실행] 을 누르세요'
        } elseif ($connected -gt 0) {
            $LblStatus.Text = '연결은 됐지만 아직 목록에 안 잡힙니다 — 폰에서 [허용] 을 누른 뒤 [새로고침] 하세요'
        } else {
            $LblStatus.Text = '폰을 찾았지만 연결하지 못했습니다 — 페어링이 풀렸을 수 있습니다. [무선 페어링] 을 해보세요'
        }
    } finally {
        $BtnDiscover.IsEnabled = $true
        $BtnRefresh.IsEnabled = $true
    }
}

# 페어링은 폰에서 사용자가 연 일회용 코드가 있어야만 가능하다. 코드는 메모리에서만 사용하고 저장하지 않는다.
function Start-WirelessPairing {
    $adbAvailable = if (-not $ADB_EXE) {
        $false
    } elseif ($ADB_EXE -eq 'adb') {
        [bool](Get-Command adb -ErrorAction SilentlyContinue)
    } else {
        Test-Path -LiteralPath $ADB_EXE -PathType Leaf
    }
    if (-not $adbAvailable) {
        [void][Windows.MessageBox]::Show(
            "adb.exe 를 찾을 수 없습니다.`n`n[설정]에서 [공식 최신 버전 설치]를 먼저 누르거나 adb.exe 위치를 지정하세요.",
            '무선 페어링', 'OK', 'Error')
        return
    }

    [xml]$pairingXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="무선 페어링" Width="460" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" Background="#202026" Foreground="#F0F0F3">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="폰에서 ‘페어링 코드로 기기 페어링’을 연 뒤, 팝업에 보이는 값을 입력하세요."
               Foreground="#D7D7DE" TextWrapping="Wrap" Margin="0,0,0,18"/>
    <TextBlock Grid.Row="1" Text="IP:포트" Foreground="#A8A8B2" Margin="0,0,0,6"/>
    <TextBox x:Name="TxtPairEndpoint" Grid.Row="2" Height="32" Padding="9,5"
             Background="#2A2A32" Foreground="#F0F0F3" BorderBrush="#454552"
             ToolTip="예: 192.168.0.5:41234"/>
    <TextBlock Grid.Row="3" Text="6자리 페어링 코드" Foreground="#A8A8B2" Margin="0,14,0,6"/>
    <PasswordBox x:Name="TxtPairCode" Grid.Row="4" Height="32" Padding="9,5"
                 Background="#2A2A32" Foreground="#F0F0F3" BorderBrush="#454552"/>
    <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,22,0,0">
      <Button x:Name="BtnPairCancel" Content="취소" MinWidth="76" Height="32" Margin="0,0,8,0"/>
      <Button x:Name="BtnPairConfirm" Content="페어링" MinWidth="76" Height="32" IsDefault="True"/>
    </StackPanel>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $pairingXaml
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $win
    $endpointBox = $dialog.FindName('TxtPairEndpoint')
    $codeBox = $dialog.FindName('TxtPairCode')
    $cancelButton = $dialog.FindName('BtnPairCancel')
    $confirmButton = $dialog.FindName('BtnPairConfirm')

    $cancelButton.Add_Click({ $dialog.Close() })
    $confirmButton.Add_Click({
        $endpoint = $endpointBox.Text.Trim()
        $code = $codeBox.Password.Trim()
        if ($endpoint -notmatch '^(?<host>(?:\d{1,3}\.){3}\d{1,3}):(?<port>\d{1,5})$' -or
            [int]$Matches.port -lt 1 -or [int]$Matches.port -gt 65535) {
            [void][Windows.MessageBox]::Show('폰의 페어링 팝업에 보이는 IPv4 주소와 포트를 입력하세요. 예: 192.168.0.5:41234', '무선 페어링', 'OK', 'Warning')
            return
        }
        $ipAddress = $null
        if (-not [System.Net.IPAddress]::TryParse($Matches.host, [ref]$ipAddress) -or
            $ipAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            [void][Windows.MessageBox]::Show('올바른 IPv4 주소를 입력하세요.', '무선 페어링', 'OK', 'Warning')
            return
        }
        if ($code -notmatch '^\d{6}$') {
            [void][Windows.MessageBox]::Show('폰에 표시된 6자리 페어링 코드를 입력하세요.', '무선 페어링', 'OK', 'Warning')
            return
        }

        $confirmButton.IsEnabled = $false
        try {
            # ProcessStartInfo.ArgumentList는 주소와 코드를 셸로 재해석하지 않고 adb에 그대로 전달한다.
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $ADB_EXE
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.ArgumentList.Add('pair')
            $psi.ArgumentList.Add($endpoint)
            $psi.ArgumentList.Add($code)
            $process = [System.Diagnostics.Process]::Start($psi)
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) {
                $detail = ($stderr + $stdout).Trim()
                if (-not $detail) { $detail = 'adb pair 명령이 실패했습니다.' }
                [void][Windows.MessageBox]::Show("페어링에 실패했습니다.`n`n$detail", '무선 페어링', 'OK', 'Error')
                return
            }

            $dialog.Close()
            Refresh-Devices
            $LblStatus.Text = '페어링 완료 — 기기 목록이 바로 비어 있으면 잠시 뒤 [새로고침]을 누르세요.'
            [void][Windows.MessageBox]::Show('페어링했습니다. 목록에 기기가 보이면 [실행]을 누르세요.', '무선 페어링', 'OK', 'Information')
        } catch {
            [void][Windows.MessageBox]::Show("페어링에 실패했습니다.`n`n$($_.Exception.Message)", '무선 페어링', 'OK', 'Error')
        } finally {
            $confirmButton.IsEnabled = $true
        }
    })
    [void]$dialog.ShowDialog()
}

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

# 프리셋 파일이 아직 없을 때 넣어주는 기본 3종.
# 여기에 없는 키는 그 항목의 Default 값이 그대로 쓰인다.
function New-DefaultPresets {
    return @{
        '평소용'   = @{ 'max-size'='1850'; 'max-fps'='120'; 'video-bit-rate'='8M';  'video-codec'='(기본)'; 'screen-off-timeout'='500'; 'keyboard'='uhid'; '__extra'='' }
        '고화질'   = @{ 'max-size'='1920'; 'max-fps'='120'; 'video-bit-rate'='16M'; 'video-codec'='h265';   'screen-off-timeout'='500'; 'keyboard'='uhid'; '__extra'='' }
        '가볍게'   = @{ 'max-size'='1080'; 'max-fps'='60';  'video-bit-rate'='4M';  'video-codec'='h265';   'screen-off-timeout'='500'; 'keyboard'='uhid'; 'turn-screen-off'=$true; '__extra'='' }
        '가로화면' = @{ 'max-size'='';     'max-fps'='120'; 'video-bit-rate'='8M';  'video-codec'='(기본)'; 'screen-off-timeout'='500'; 'keyboard'='uhid'; 'new-display'='1920x1080'; '__extra'='' }
    }
}

# phonepref 토글들의 현재 상태를 폰에서 읽어와 화면에 반영한다.
# (추측해서 보여주면 실제 폰 상태와 어긋나므로 항상 읽어서 맞춘다)
function Sync-PhonePrefs {
    foreach ($opt in ($OPTIONS | Where-Object { $_.Type -eq 'phonepref' })) {
        $c = $Controls[$opt.Key]
        try {
            $raw = (& $ADB_EXE shell settings get $opt.SettingNs $opt.SettingKey 2>$null | Select-Object -First 1)
            $c.IsChecked = ([string]$raw).Trim() -eq '1'
        } catch { }
    }
}

function Read-Presets {
    if (Test-Path $PRESET_FILE) {
        try { $script:Presets = Get-Content $PRESET_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable }
        catch { $script:Presets = @{} }
    }
    if (-not $script:Presets -or $script:Presets.Count -eq 0) {
        $script:Presets = New-DefaultPresets
        Write-Presets
    }
    $CmbPreset.Items.Clear()
    [void]$CmbPreset.Items.Add('(선택 안 함)')
    foreach ($k in ($script:Presets.Keys | Sort-Object)) { [void]$CmbPreset.Items.Add($k) }
    $CmbPreset.SelectedIndex = 0
}

function Write-Presets {
    $script:Presets | ConvertTo-Json -Depth 5 | Set-Content -Path $PRESET_FILE -Encoding UTF8
}

function Get-CurrentValues {
    $h = @{}
    foreach ($opt in $OPTIONS) {
        if ($opt.Type -in @('phonepref','path')) { continue }   # 폰 상태·PC 경로라 프리셋에 저장하지 않음
        $c = $Controls[$opt.Key]
        switch ($opt.Type) {
            'check'     { $h[$opt.Key] = [bool]$c.IsChecked }
            'combo'     { $h[$opt.Key] = [string]$c.SelectedItem }
            'editcombo' { $h[$opt.Key] = (([string]$c.Text -split '\s{2,}')[0]).Trim() }
            default     { $h[$opt.Key] = [string]$c.Text }
        }
    }
    $h['__extra'] = $TxtExtra.Text
    if ($null -ne $script:stayAwakeBeforeScreenOff) { $h['__stay-awake-before-screen-off'] = [bool]$script:stayAwakeBeforeScreenOff }
    if ($null -ne $script:noControlBeforeScreenOff) { $h['__no-control-before-screen-off'] = [bool]$script:noControlBeforeScreenOff }
    return $h
}

function Set-Values {
    param($Values)
    $script:ready = $false
    $script:powerOptionsUpdating = $true
    try {
        if ($Values.ContainsKey('__stay-awake-before-screen-off')) {
            $script:stayAwakeBeforeScreenOff = [bool]$Values['__stay-awake-before-screen-off']
        }
        if ($Values.ContainsKey('__no-control-before-screen-off')) {
            $script:noControlBeforeScreenOff = [bool]$Values['__no-control-before-screen-off']
        }
        foreach ($opt in $OPTIONS) {
            if ($opt.Type -in @('phonepref','path')) { continue }
            if (-not $Values.ContainsKey($opt.Key)) { continue }
            $c = $Controls[$opt.Key]
            switch ($opt.Type) {
                'check'     { $c.IsChecked = [bool]$Values[$opt.Key] }
                'combo'     { if ($c.Items.Contains($Values[$opt.Key])) { $c.SelectedItem = $Values[$opt.Key] } }
                'editcombo' { $c.Text = [string]$Values[$opt.Key] }   # Text 만 세팅 (SelectedItem 은 WPF 가 알아서 맞춤)
                default     { $c.Text = [string]$Values[$opt.Key] }
            }
        }
        if ($Values.ContainsKey('__extra')) { $TxtExtra.Text = [string]$Values['__extra'] }
    } finally {
        $script:powerOptionsUpdating = $false
    }
    Update-PowerOptionState
    $script:ready = $true
    Update-Preview
}

# ---------- 이벤트 ----------
$NavList.Add_SelectionChanged({
    $g = [string]$NavList.SelectedItem
    if ($g -and $Pages.ContainsKey($g)) {
        $OptionHost.Children.Clear()
        [void]$OptionHost.Children.Add($Pages[$g])
    }
})

$BtnRefresh.Add_Click({ Refresh-Devices; Sync-PhonePrefs; Update-Preview })
$BtnDiscover.Add_Click({ Find-WirelessDevices; Sync-PhonePrefs; Update-Preview })
$BtnPair.Add_Click({ Start-WirelessPairing })
$CmbDevice.Add_SelectionChanged({ Update-Preview })
$TxtExtra.Add_TextChanged({ Update-Preview })
$Controls['turn-screen-off'].Add_Checked({ Update-PowerOptionState; Update-Preview })
$Controls['turn-screen-off'].Add_Unchecked({ Update-PowerOptionState; Update-Preview })
$Controls['no-control'].Add_Checked({
    if ($script:powerOptionsUpdating) { return }
    if ($Controls['turn-screen-off'].IsChecked) { $Controls['turn-screen-off'].IsChecked = $false }
    Update-PowerOptionState
    Update-Preview
})

$CmbPreset.Add_SelectionChanged({
    $name = [string]$CmbPreset.SelectedItem
    if ($name -and $name -ne '(선택 안 함)' -and $script:Presets.ContainsKey($name)) {
        Set-Values $script:Presets[$name]
        $TxtPresetName.Text = $name
        $LblStatus.Text = "프리셋 '$name' 불러옴"
    }
})

$BtnPresetSave.Add_Click({
    $name = $TxtPresetName.Text.Trim()
    if (-not $name) { $name = [string]$CmbPreset.SelectedItem }
    if (-not $name -or $name -eq '(선택 안 함)') {
        $LblStatus.Text = '저장할 프리셋 이름을 입력하세요'
        return
    }
    $script:Presets[$name] = Get-CurrentValues
    Write-Presets
    Read-Presets
    $CmbPreset.SelectedItem = $name
    $LblStatus.Text = "프리셋 '$name' 저장됨"
})

$BtnPresetDel.Add_Click({
    $name = [string]$CmbPreset.SelectedItem
    if (-not $name -or $name -eq '(선택 안 함)') { return }
    $script:Presets.Remove($name)
    Write-Presets
    Read-Presets
    $LblStatus.Text = "프리셋 '$name' 삭제됨"
})

$BtnCopy.Add_Click({
    Set-Clipboard -Value $TxtCmd.Text
    $LblStatus.Text = '명령어를 클립보드에 복사했습니다'
})

$BtnBat.Add_Click({
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = '배치 파일 (*.bat)|*.bat'
    $dlg.FileName = 'scrcpy_my.bat'
    $dlg.InitialDirectory = $SCRCPY_DIR
    if (-not $dlg.ShowDialog()) { return }
    $conflicts = @(Get-ScrcpyOptionConflicts)
    if ($conflicts.Count) {
        [void][Windows.MessageBox]::Show(($conflicts -join "`n"), '서로 같이 쓸 수 없는 옵션', 'OK', 'Warning')
        return
    }
    $adbForBat = if ($ADB_EXE -and $ADB_EXE -ne 'adb' -and (Test-Path -LiteralPath $ADB_EXE)) {
        $ADB_EXE
    } else {
        (Get-Command adb -ErrorAction SilentlyContinue).Source
    }
    if (-not $adbForBat -or -not (Test-Path -LiteralPath $adbForBat)) {
        [void][Windows.MessageBox]::Show(
            "adb.exe 를 찾을 수 없어 PATH에 의존하지 않는 BAT를 만들 수 없습니다.`n`n[설정]에서 [공식 최신 버전 설치]를 먼저 누르거나 adb.exe 위치를 지정하세요.",
            '.bat 로 저장', 'OK', 'Error')
        return
    }
    $argLine = (Format-Cmd (Get-ScrcpyArgs)) -replace '^scrcpy ', ''
    $content = @"
@echo off
chcp 65001 >nul
setlocal
set "ADB_EXE=$adbForBat"
if not exist "%ADB_EXE%" (
  echo [실패] adb.exe 를 찾을 수 없습니다: %ADB_EXE%
  pause
  exit /b 1
)
taskkill /f /im scrcpy.exe >nul 2>&1
"%ADB_EXE%" devices >nul
timeout /t 2 /nobreak >nul
"$SCRCPY_EXE" $argLine
if errorlevel 1 pause
endlocal
"@
    Set-Content -Path $dlg.FileName -Value $content -Encoding UTF8
    $LblStatus.Text = "저장됨: $($dlg.FileName)"
})

$BtnRun.Add_Click({
    # 지금 안 붙어 있는 기기를 골라둔 채 실행하면 scrcpy 가 그냥 실패한다. 먼저 붙이도록 안내한다.
    if ($script:OfflineLabels.Contains([string]$CmbDevice.SelectedItem)) {
        [void][Windows.MessageBox]::Show(
            "고른 기기가 지금 연결돼 있지 않습니다.`n`n[기기 찾기] 를 눌러 연결한 뒤 실행하세요.",
            'scrcpy 설정', 'OK', 'Warning')
        return
    }
    if (-not $SCRCPY_EXE -or -not (Test-Path $SCRCPY_EXE)) {
        [void][Windows.MessageBox]::Show(
            "scrcpy.exe 를 찾을 수 없습니다.`n`n설정 탭에서 [공식 최신 버전 설치]를 누르거나, 이미 설치했다면 [찾아보기]로 scrcpy.exe를 선택하세요.",
            'scrcpy 설정')
        return
    }
    $conflicts = @(Get-ScrcpyOptionConflicts)
    if ($conflicts.Count) {
        [void][Windows.MessageBox]::Show(($conflicts -join "`n"), '서로 같이 쓸 수 없는 옵션', 'OK', 'Warning')
        return
    }
    try {
        # ※ Start-Process -ArgumentList 배열은 값에 공백이 있으면 인자를 쪼개버린다(실측:
        #   --window-title=가상화면 1920x1080 → '1920x1080' 이 별개 인자가 되어 실행 실패).
        #   ProcessStartInfo.ArgumentList 는 각 인자를 알아서 안전하게 넘겨준다.
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $SCRCPY_EXE
        $psi.WorkingDirectory = $SCRCPY_DIR
        $psi.UseShellExecute = $false
        foreach ($a in (Get-ScrcpyArgs)) { $psi.ArgumentList.Add($a) }
        [void][System.Diagnostics.Process]::Start($psi)
        $LblStatus.Text = '실행했습니다. 창이 안 뜨면 폰의 무선 디버깅을 확인하세요.'
    } catch {
        [void][Windows.MessageBox]::Show("실행 실패:`n$_", 'scrcpy 설정')
    }
})

# 창을 닫을 때 현재 값을 통째로 저장해두고, 다음에 켤 때 그대로 복원한다.
# (프리셋과 별개 — 프리셋은 사람이 이름 붙여 고르는 것, 이건 "하던 대로" 이어받기용)
$win.Add_Closing({
    try { Get-CurrentValues | ConvertTo-Json -Depth 5 | Set-Content -Path $LAST_FILE -Encoding UTF8 } catch { }
})

function Restore-LastValues {
    if (-not (Test-Path $LAST_FILE)) { return }
    try {
        $last = Get-Content $LAST_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        if ($last) { Set-Values $last }
    } catch { }
}

# ---------- 시작 ----------
$script:ready = $true
$NavList.SelectedIndex = 0
Refresh-Devices
Sync-PhonePrefs
Read-Presets
Restore-LastValues
Update-PowerOptionState
Update-Preview

[void]$win.ShowDialog()
