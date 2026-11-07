param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$ExpectedUuid,[switch]$Benchmark,[switch]$LegacyDrag)
$ErrorActionPreference='Stop'
if($RunId -notmatch '^[A-Za-z0-9-]+$'){throw 'Invalid nonce'}
if(([Guid](Get-CimInstance Win32_ComputerSystemProduct).UUID) -ne ([Guid]$ExpectedUuid)){throw 'Guest UUID mismatch'}
$args="-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\BackgroundLab\payload\tools\Guest-Preflight20.ps1 -RunId $RunId -ExpectedUuid $ExpectedUuid"
if($Benchmark){$args+=' -ActionsPerRound 200 -Rounds 3'}
if($LegacyDrag){$args+=' -LegacyDrag'}
$action=New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument $args
$principal=New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\TestAgent" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName BcuPreflight20 -Action $action -Principal $principal -Force|Out-Null
Start-ScheduledTask -TaskName BcuPreflight20
