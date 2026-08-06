# =============================================================
#  무선 연결 — 기기 목록·재연결·페어링
# =============================================================

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

# adb 는 붙기까지 몇 초 걸린다 — 끊긴 직후엔 목록이 비었다가 offline 을 거쳐 device 가 된다(실측).
# 그래서 한 번 보고 판단하지 않고, 정해진 시간 동안 지켜본다. 붙으면 $true.
function Wait-DeviceOnline {
    param([int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $found = Get-AdbDevices
        if (@($found | Where-Object { $_.State -eq 'device' }).Count -gt 0) { return $true }
        if (@($found | Where-Object { $_.State -eq 'offline' }).Count -gt 0) {
            Update-Ui '기기 찾는 중 — 폰이 응답하기 시작했습니다…'
        }
        Wait-Ui 700
    } while ((Get-Date) -lt $deadline)
    return $false
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
#   ① adb devices 폴링       — 데몬이 멀쩡하면 알아서 붙는다 (몇 초 걸린다)
#   ② adb 데몬 재시작 + 폴링 — 오래 뜬 데몬은 mDNS 탐색이 죽어 있다. 이게 실제 복구 경로다
#   ③ adb mdns services      — 광고에서 IP:포트를 직접 캐낸다 (②로도 안 될 때)
#   ④ TCP probe → connect    — 살아 있는 후보만 남겨 붙인다 (죽은 주소로 connect 하면 오래 매달린다)
# ※ 이 폰은 기기 ID 가 mDNS 이름이라 그 이름으로는 connect 가 안 된다(실측). 그래서 ③이 필요하다.
function Find-WirelessDevices {
    if (-not $ADB_EXE) {
        [void][Windows.MessageBox]::Show('adb.exe 를 찾을 수 없습니다. [설정] 에서 지정하거나 [공식 최신 버전 설치]를 누르세요.', '기기 찾기', 'OK', 'Error')
        return
    }

    $BtnDiscover.IsEnabled = $false
    $BtnRefresh.IsEnabled = $false
    try {
        # ① 데몬이 멀쩡하면 알아서 붙는다. 다만 즉시가 아니다 —
        #    끊긴 직후엔 목록이 비었다가 offline 을 거쳐 device 가 된다(실측 2026-08-03).
        Update-Ui '기기 찾는 중 — 폰이 스스로 붙기를 기다립니다…'
        if (Wait-DeviceOnline 5) {
            Refresh-Devices
            $LblStatus.Text = '연결됐습니다 — [실행] 을 누르세요'
            return
        }

        # ② adb 데몬을 다시 시작한다. **오래 떠 있던 데몬은 mDNS 탐색이 죽어 있다**(실측 2026-08-03):
        #    재시작 전에는 `adb mdns services` 가 끊긴 상태에서도 8초 내내 빈 목록이었는데,
        #    kill-server 직후에는 폰이 바로 잡히고 12초 뒤 연결까지 됐다. 이게 실제 복구 경로다.
        #    ※ 이 단계는 열려 있는 미러링 창을 끊는다 — 그래서 누르기 전에 알린다.
        Update-Ui 'adb 를 다시 시작합니다 — 열려 있는 미러링 창이 끊길 수 있습니다…'
        try { & $ADB_EXE kill-server 2>$null | Out-Null } catch { }
        Wait-Ui 800
        if (Wait-DeviceOnline 18) {
            Refresh-Devices
            $LblStatus.Text = '연결됐습니다 — [실행] 을 누르세요'
            return
        }

        # ③ 그래도 안 붙으면 mDNS 광고에서 IP:포트를 직접 캐낸다.
        #    출력 형식(실측): `adb-R3CW…<TAB>_adb-tls-connect._tcp<TAB>192.168.1.131:45077` — 같은 줄이 여러 번 나온다.
        $candidates = [System.Collections.Generic.List[string]]::new()
        $mdnsDeadline = (Get-Date).AddSeconds(3)   # 빈손으로 끝나는 게 보통이라 길게 붙잡지 않는다
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
        } while ((Get-Date) -lt $mdnsDeadline)

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
            $runPair = {
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
                [pscustomobject]@{ ExitCode = $process.ExitCode; Detail = ($stderr + $stdout).Trim() }
            }

            $result = & $runPair
            # 오래 떠 있던 adb 데몬은 TLS 페어링 핸드셰이크가 깨져 있다(실측: Find-WirelessDevices의
            # kill-server 복구 경로와 동일 원인). "protocol fault" 는 이 증상의 표식이라 한 번만 자동 재시도한다.
            if ($result.ExitCode -ne 0 -and $result.Detail -match 'protocol fault') {
                Update-Ui '페어링 재시도 — adb 를 다시 시작합니다…'
                try { & $ADB_EXE kill-server 2>$null | Out-Null } catch { }
                Wait-Ui 800
                $result = & $runPair
            }

            if ($result.ExitCode -ne 0) {
                $detail = $result.Detail
                if (-not $detail) { $detail = 'adb pair 명령이 실패했습니다.' }
                # 실측(2026-08-06): Windows 네트워크 프로필이 "공용"이면 방화벽이 로컬 LAN 페어링
                # 연결을 막아 이 에러가 난다. adb 재시작으로도 안 풀리고 "개인"으로 바꾸면 즉시 해결됐다.
                if ($detail -match 'protocol fault') {
                    $detail += "`n`n이 오류는 Windows 네트워크 프로필이 '공용'일 때 방화벽이 폰과의 로컬 연결을 막아서 나는 경우가 흔합니다.`n[설정] > [네트워크 및 인터넷] > 지금 연결된 네트워크 > 네트워크 프로필 유형을 '개인'으로 바꾼 뒤 다시 시도해 보세요."
                }
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
