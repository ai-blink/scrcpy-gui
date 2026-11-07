param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][Guid]$ExpectedUuid,[switch]$Benchmark)
$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystemProduct).UUID -ne '71EC4D56-B8A9-A48C-92E8-E83EE248EC83'){throw 'Not the approved preparation clone'}
if($RunId -notmatch '^[a-f0-9]{32}$'){throw 'Invalid nonce'}
$extra=if($Benchmark){'-ActionsPerRound 200 -Rounds 3'}else{''}
$code=@"
`$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'QEMU'){exit 0}
if(([Guid](Get-CimInstance Win32_ComputerSystemProduct).UUID) -ne ([Guid]'$ExpectedUuid')){throw 'Unexpected QEMU identity'}
if(Test-Path 'C:\BackgroundLab\preflight\$RunId\summary.json'){exit 0}
Start-Sleep -Seconds 15
& 'C:\BackgroundLab\payload\tools\Guest-Preflight20.ps1' -RunId '$RunId' -ExpectedUuid '$ExpectedUuid' $extra
"@
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
$action=New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded"
$user="$env:COMPUTERNAME\TestAgent"
$principal=New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName BcuQemuPreflightOnce -Action $action -Principal $principal -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user) -Force|Out-Null
@{runId=$RunId;expectedUuid=$ExpectedUuid.ToString();trigger='TestAgent logon; QEMU UUID guarded'}|ConvertTo-Json|Set-Content C:\BackgroundLab\qemu-preflight-staged.json
