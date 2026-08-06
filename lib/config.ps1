# =============================================================
#  설정·프리셋 저장/복원 + 옵션 표
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
$PRESET_FILE = Join-Path $ProjectRoot 'scrcpy-gui-presets.json'
$LAST_FILE   = Join-Path $ProjectRoot 'scrcpy-gui-last.json'   # 창 닫을 때 현재 값 자동 저장 → 다음에 켜면 복원
$CONFIG_FILE = Join-Path $ProjectRoot 'scrcpy-gui-config.json' # scrcpy·adb 실행 파일 위치 (PC마다 다름)

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

$script:Config = Read-Config

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

function Restore-LastValues {
    if (-not (Test-Path $LAST_FILE)) { return }
    try {
        $last = Get-Content $LAST_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        if ($last) { Set-Values $last }
    } catch { }
}
