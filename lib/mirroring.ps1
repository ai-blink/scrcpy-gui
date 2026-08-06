# =============================================================
#  옵션 조립 · 명령어 미리보기 · 실행 인자
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
