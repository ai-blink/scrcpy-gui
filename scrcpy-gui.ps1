param(
    [switch]$ValidateOnly
)

# =============================================================
#  scrcpy 설정 GUI  v0.1.7-beta   (Windows / PowerShell 7 + WPF)
#  https://github.com/ai-blink/scrcpy-gui                MIT License
#
#  진입점 — lib/ 아래 모듈을 순서대로 불러온 뒤 창을 띄운다.
#  옵션 추가/변경은 lib/config.ps1 의 $OPTIONS 표에서 한다.
# =============================================================

# 이 파일 자신의 폴더가 프로젝트 루트. lib/*.ps1 은 dot-source 되므로
# 그 안에서 $PSScriptRoot 를 쓰면 lib 폴더 자신을 가리켜 버린다 — 그래서 여기서 한 번만 구해 넘긴다.
$ProjectRoot = $PSScriptRoot

. (Join-Path $ProjectRoot 'lib\config.ps1')
. (Join-Path $ProjectRoot 'lib\exe-discovery.ps1')

if ($ValidateOnly) {
    Get-OfficialScrcpyRelease | ConvertTo-Json -Compress
    return
}

. (Join-Path $ProjectRoot 'lib\ui.ps1')
. (Join-Path $ProjectRoot 'lib\wireless.ps1')
. (Join-Path $ProjectRoot 'lib\mirroring.ps1')

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
    # 무선 미러링은 창이 뜰 때까지 몇 초 걸릴 수 있다 — 그 사이 재클릭하면 scrcpy.exe가 중복 실행된다.
    $BtnRun.IsEnabled = $false
    try {
        # ※ Start-Process -ArgumentList 배열은 값에 공백이 있으면 인자를 쪼개버린다(실측:
        #   --window-title=가상화면 1920x1080 → '1920x1080' 이 별개 인자가 되어 실행 실패).
        #   ProcessStartInfo.ArgumentList 는 각 인자를 안전하게 넘겨준다.
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $SCRCPY_EXE
        $psi.WorkingDirectory = $SCRCPY_DIR
        $psi.UseShellExecute = $false
        foreach ($a in (Get-ScrcpyArgs)) { $psi.ArgumentList.Add($a) }
        [void][System.Diagnostics.Process]::Start($psi)
        $LblStatus.Text = '실행했습니다. 창이 안 뜨면 폰의 무선 디버깅을 확인하세요.'
        Wait-Ui 2000
    } catch {
        [void][Windows.MessageBox]::Show("실행 실패:`n$_", 'scrcpy 설정')
    } finally {
        $BtnRun.IsEnabled = $true
    }
})

# 창을 닫을 때 현재 값을 통째로 저장해두고, 다음에 켤 때 그대로 복원한다.
# (프리셋과 별개 — 프리셋은 사람이 이름 붙여 고르는 것, 이건 "하던 대로" 이어받기용)
$win.Add_Closing({
    try { Get-CurrentValues | ConvertTo-Json -Depth 5 | Set-Content -Path $LAST_FILE -Encoding UTF8 } catch { }
})

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
