param([Parameter(Mandatory)][string]$BatchId)
$ErrorActionPreference='Stop'
if([Guid](Get-CimInstance Win32_ComputerSystemProduct).UUID -ne [Guid]'71ec4d56-b8a9-a48c-92e8-e83ee248ec83'){throw 'Wrong preparation VM'}
if($BatchId -notmatch '^[a-f0-9]{32}$'){throw 'Bad batch ID'}
Get-ScheduledTask -TaskName BcuQemuPreflightOnce -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null
$sid=(Get-LocalUser TestAgent).SID.Value
$desktop="Registry::HKEY_USERS\$sid\Control Panel\Desktop"
New-ItemProperty -Path $desktop -Name LogPixels -Value 96 -PropertyType DWord -Force|Out-Null
New-ItemProperty -Path $desktop -Name Win8DpiScaling -Value 1 -PropertyType DWord -Force|Out-Null
$code="Start-Sleep -Seconds 20; & C:\BackgroundLab\performance\Guest-Batch.ps1 -BatchId $BatchId"
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
$a=New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded"
$u="$env:COMPUTERNAME\TestAgent"
$p=New-ScheduledTaskPrincipal -UserId $u -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName BcuAppPerformanceOnce -Principal $p -Action $a -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $u) -Force|Out-Null
