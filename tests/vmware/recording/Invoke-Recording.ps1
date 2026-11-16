[CmdletBinding()]
param(
 [string]$Scenes='tabs,preset,remote,mirror',
 [string]$AppExe=(Join-Path $PSScriptRoot '..\..\..\app\ScrcpyGui.exe'),
 [string]$ScrcpyDir='C:\app\scrcpy-win64-v4.1',
 [string]$EmulatorAdbPort='5801',
 [int]$TimeoutSeconds=600
)
# 포트폴리오 GIF 녹화 실행기.
# - 호스트 입력·창 활성화 없음. 모든 GUI 입력은 VM(TestAgent 세션) 안에서만.
# - 실제 폰 대신 호스트의 창 없는 에뮬레이터(adb 5039, 포트 5800/5801)를 쓴다.
# - 호스트는 연결을 기다리지 않는다(방화벽 알림 방지). 호스트 → 게스트 방향 중계만.
# - 잠금 파일로 같은 VM 동시 사용을 막고, 끝나면 VM 끄기 · 네트워크 다시 끄기.
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$lab=Join-Path $repo 'work\vmware-background'; $vmx=Join-Path $lab 'Background-Test.vmx'
$vmrun='C:\Program Files\VMware\VMware Workstation\vmrun.exe'
$py='C:\dev\venvs\common-py313\Scripts\python.exe'
$runId=[Guid]::NewGuid().ToString('N'); $out=Join-Path $repo "work\recordings\$runId"; New-Item -ItemType Directory $out -Force|Out-Null
function Log([string]$m){ $line=(Get-Date -Format 'HH:mm:ss')+' '+$m; Write-Host $line; Add-Content (Join-Path $out 'host.log') $line -Encoding utf8 }

# 0. 동시 실행 잠금 (프로세스가 죽으면 핸들과 함께 풀린다)
$lockPath=Join-Path $lab 'recording.lock'
try{ $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }catch{ throw "다른 세션이 녹화 VM을 쓰는 중입니다: $lockPath" }
$info=[Text.Encoding]::UTF8.GetBytes("pid=$PID run=$runId start=$(Get-Date -Format s)"); $lock.SetLength(0); $lock.Write($info,0,$info.Length); $lock.Flush()
$relay=$null; $stopFile=Join-Path $out 'relay.stop'; $netOn=$false
try{
 if(Get-Process vmware -ErrorAction SilentlyContinue){throw 'VMware 콘솔 창이 열려 있으면 무인 실행을 하지 않습니다'}
 if((& $vmrun list) -contains $vmx){throw '녹화 VM이 이미 켜져 있습니다(다른 작업 확인 필요)'}
 $cred=Get-Content (Join-Path $lab 'guest-admin-credentials.json') -Raw|ConvertFrom-Json
 function G([string[]]$a){ & $vmrun -gu $cred.username -gp $cred.password @a; if($LASTEXITCODE){throw "vmrun $($a[0]) 실패 ($LASTEXITCODE)"} }

 # 1. 에뮬레이터 확인 후 호스트 쪽 분리 adb(5039)를 내려 에뮬레이터 adb 포트를 비운다
 $hostAdb='C:\dev\android\Sdk\platform-tools\adb.exe'
 $env:ADB_MDNS='0'
 # 에뮬레이터는 부팅 때만 adb 서버에 알리므로, 서버 목록 대신 에뮬레이터 adb 포트가 열려 있는지 본다
 if(-not (Get-NetTCPConnection -State Listen -LocalAddress 127.0.0.1 -LocalPort ([int]$EmulatorAdbPort) -ErrorAction SilentlyContinue)){throw "가상 폰 adb 포트($EmulatorAdbPort)가 열려 있지 않습니다 — 에뮬레이터를 먼저 띄우세요"}
 if(Get-NetTCPConnection -State Listen -LocalPort 5039 -ErrorAction SilentlyContinue){ & $hostAdb -P 5039 kill-server 2>&1|Out-Null }
 Log '가상 폰 확인, 호스트 분리 adb 종료'

 # 2. VM 네트워크(호스트 전용) 켜기
 $text=[IO.File]::ReadAllText($vmx)
 if(-not $text.Contains('ethernet0.connectionType = "hostonly"')){throw 'VM 네트워크가 호스트 전용이 아닙니다'}
 [IO.File]::WriteAllText($vmx,$text.Replace('ethernet0.present = "FALSE"','ethernet0.present = "TRUE"')); $netOn=$true
 Log 'VM 호스트 전용 네트워크 켬'

 # 3. VM 시작과 TestAgent 데스크톱 대기
 & $vmrun -T ws start $vmx nogui; if($LASTEXITCODE){throw 'VM 시작 실패'}
 $ready=$false
 for($i=0;$i -lt 90;$i++){ $ps=& $vmrun -gu $cred.username -gp $cred.password listProcessesInGuest $vmx 2>$null; if($LASTEXITCODE -eq 0 -and ($ps -match 'TestAgent, cmd=explorer.exe')){$ready=$true;break}; Start-Sleep 2 }
 if(-not $ready){throw 'TestAgent 데스크톱이 준비되지 않았습니다'}
 $ip=(& $vmrun -gu $cred.username -gp $cred.password getGuestIPAddress $vmx -wait).Trim()
 if($ip -notmatch '^192\.168\.102\.\d+$'){throw "예상 밖 게스트 주소: $ip"}
 Log "VM 준비, 게스트 주소 $ip"

 # 4. 파일 전달
 $stage=Join-Path $out 'stage'; New-Item -ItemType Directory $stage -Force|Out-Null
 Compress-Archive -Path $ScrcpyDir -DestinationPath (Join-Path $stage 'scrcpy.zip') -Force
 & $vmrun -gu $cred.username -gp $cred.password createDirectoryInGuest $vmx 'C:\BackgroundLab\rec' 2>$null
 & $vmrun -gu $cred.username -gp $cred.password createDirectoryInGuest $vmx 'C:\BackgroundLab\rec\in' 2>$null
 # 게스트용 설정 사본: 가상 폰은 h265 인코딩이 실패하고(2026-11-10 실측), 화면 끄기는 녹화에 불필요.
 # 실제 폰 기기 ID는 넣지 않는다. 사용자 원본 파일은 읽기만 한다.
 function Patch($o){ foreach($k in @($o.PSObject.Properties.Name)){ $v=$o.$k; if($v -is [pscustomobject]){Patch $v} }
  if($o.PSObject.Properties.Name -contains 'video-codec'){ foreach($kv in @(@('video-codec','h264'),@('turn-screen-off',$false),@('screen-off-timeout',''),@('no-audio',$true),@('window-height','820'))){ $o|Add-Member -NotePropertyName $kv[0] -NotePropertyValue $kv[1] -Force } } }
 $last=Get-Content 'C:\app\scrcpy-gui\scrcpy-gui-last.json' -Raw|ConvertFrom-Json; Patch $last
 foreach($k in '__deviceId','__deviceMode'){ $last.PSObject.Properties.Remove($k) }
 $last|ConvertTo-Json -Depth 8|Set-Content (Join-Path $stage 'scrcpy-gui-last.json') -Encoding utf8
 $presets=Get-Content 'C:\app\scrcpy-gui\scrcpy-gui-presets.json' -Raw|ConvertFrom-Json
 # 항목이 빠진 프리셋은 기본값(h265)으로 돌아갈 수 있어 모든 프리셋에 명시한다
 foreach($pp in $presets.PSObject.Properties){ if($pp.Value -is [pscustomobject]){ $pp.Value|Add-Member -NotePropertyName 'video-codec' -NotePropertyValue 'h264' -Force; Patch $pp.Value } }
 $presets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $stage 'scrcpy-gui-presets.json') -Encoding utf8
 $files=@{
  'Guest-Relay.ps1'=(Join-Path $PSScriptRoot 'Guest-Relay.ps1'); 'Guest-Record.ps1'=(Join-Path $PSScriptRoot 'Guest-Record.ps1')
  'in\scrcpy.zip'=(Join-Path $stage 'scrcpy.zip'); 'in\ScrcpyGui.exe'=(Resolve-Path $AppExe).Path
  'in\scrcpy-gui-presets.json'=(Join-Path $stage 'scrcpy-gui-presets.json'); 'in\scrcpy-gui-last.json'=(Join-Path $stage 'scrcpy-gui-last.json')
  'in\scrcpy-gui-remote.json'='C:\app\scrcpy-gui\scrcpy-gui-remote.json'
 }
 foreach($k in $files.Keys){ G @('CopyFileFromHostToGuest',$vmx,$files[$k],"C:\BackgroundLab\rec\$k") }
 Log '파일 전달 완료'

 # 5. 게스트 준비(관리자): 앱 배치 · 방화벽(게스트) · 중계 작업 · 녹화 작업
 $code=@"
`$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystemProduct).UUID -ne '71EC4D56-B8A9-A48C-92E8-E83EE248EC83'){throw 'Guest identity mismatch'}
New-Item -ItemType Directory C:\app\scrcpy-gui -Force|Out-Null
Expand-Archive C:\BackgroundLab\rec\in\scrcpy.zip -DestinationPath C:\app -Force
Copy-Item C:\BackgroundLab\rec\in\ScrcpyGui.exe,C:\BackgroundLab\rec\in\scrcpy-gui-presets.json,C:\BackgroundLab\rec\in\scrcpy-gui-last.json,C:\BackgroundLab\rec\in\scrcpy-gui-remote.json C:\app\scrcpy-gui\ -Force
icacls C:\app /grant 'Users:(OI)(CI)M' /T /Q|Out-Null
icacls C:\BackgroundLab\rec /grant 'Users:(OI)(CI)M' /T /Q|Out-Null
if(-not (Get-NetFirewallRule -DisplayName BackgroundLabAdbRelay -ErrorAction SilentlyContinue)){New-NetFirewallRule -DisplayName BackgroundLabAdbRelay -Direction Inbound -Protocol TCP -LocalPort 25801 -Action Allow -Profile Any|Out-Null}
`$a=New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\BackgroundLab\rec\Guest-Relay.ps1'
Register-ScheduledTask -TaskName BackgroundLabAdbRelay -Action `$a -User SYSTEM -RunLevel Highest -Force|Out-Null
Stop-ScheduledTask -TaskName BackgroundLabAdbRelay -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName BackgroundLabAdbRelay
`$a=New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\BackgroundLab\rec\Guest-Record.ps1 -RunId $runId -Scenes $Scenes'
`$p=New-ScheduledTaskPrincipal -UserId "`$env:COMPUTERNAME\TestAgent" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName BackgroundLabRecord -Action `$a -Principal `$p -Force|Out-Null
Start-Sleep 2
Start-ScheduledTask -TaskName BackgroundLabRecord
"@
 # 중계부터 띄운다: 호스트 쪽은 게스트 25801로 접속을 계속 재시도한다
 $relay=Start-Process $py -ArgumentList @((Join-Path $PSScriptRoot 'host_relay.py'),$ip,'25801',$EmulatorAdbPort,"`"$stopFile`"") -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $out 'host-relay.log') -RedirectStandardError (Join-Path $out 'host-relay.err.log')
 G @('runProgramInGuest',$vmx,'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code)))
 Log '게스트 준비·녹화 시작'

 # 6. 결과 회수
 $zip=Join-Path $out 'guest.zip'; $watch=[Diagnostics.Stopwatch]::StartNew(); $got=$false
 while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds){
  Start-Sleep 5
  & $vmrun -gu $cred.username -gp $cred.password CopyFileFromGuestToHost $vmx "C:\BackgroundLab\rec\$runId.zip" $zip 2>$null|Out-Null
  if($LASTEXITCODE -eq 0){$got=$true;break}
 }
 & $vmrun -gu $cred.username -gp $cred.password CopyFileFromGuestToHost $vmx 'C:\BackgroundLab\rec\relay.log' (Join-Path $out 'guest-relay.log') 2>$null|Out-Null
 & $vmrun -gu $cred.username -gp $cred.password CopyFileFromGuestToHost $vmx "C:\BackgroundLab\rec\$runId\record.log" (Join-Path $out 'record.log') 2>$null|Out-Null
 # 녹화 작업이 비정상 종료했는지(작업 결과 코드) 남긴다
 $q=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("(Get-ScheduledTaskInfo -TaskName BackgroundLabRecord|Select-Object LastRunTime,LastTaskResult|ConvertTo-Json)|Set-Content C:\BackgroundLab\rec\task-info.json"))
 & $vmrun -gu $cred.username -gp $cred.password runProgramInGuest $vmx 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -EncodedCommand $q 2>$null|Out-Null
 & $vmrun -gu $cred.username -gp $cred.password CopyFileFromGuestToHost $vmx 'C:\BackgroundLab\rec\task-info.json' (Join-Path $out 'task-info.json') 2>$null|Out-Null
 if(-not $got){throw '게스트 녹화 결과 시간 초과'}
 Expand-Archive $zip -DestinationPath (Join-Path $out 'guest') -Force
 Log ('게스트 결과: '+(Get-Content (Join-Path $out 'guest\summary.json') -Raw))
}finally{
 'stop'|Set-Content $stopFile
 if($relay -and -not $relay.HasExited){ $relay.WaitForExit(3000)|Out-Null; if(-not $relay.HasExited){Stop-Process -Id $relay.Id -Force} }
 if((& $vmrun list) -contains $vmx){ & $vmrun -T ws stop $vmx soft|Out-Null; if($LASTEXITCODE){& $vmrun -T ws stop $vmx hard|Out-Null} }
 if($netOn){ for($i=0;$i -lt 30 -and ((& $vmrun list) -contains $vmx);$i++){Start-Sleep 1}; $t=[IO.File]::ReadAllText($vmx); [IO.File]::WriteAllText($vmx,$t.Replace('ethernet0.present = "TRUE"','ethernet0.present = "FALSE"')); Log 'VM 끄고 네트워크 다시 끔' }
 $lock.Dispose(); Remove-Item $lockPath -ErrorAction SilentlyContinue
}
# 7. GIF
if(Test-Path (Join-Path $out 'guest')){ & $py (Join-Path $PSScriptRoot 'make_gifs.py') (Join-Path $out 'guest') (Join-Path $out 'gif') }
Write-Output "결과: $out"
