$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'Prepare the approved VMware clone only'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
if(-not(Test-Path C:\BackgroundLab\qga)){[IO.Compression.ZipFile]::ExtractToDirectory('C:\BackgroundLab\qga.zip','C:\BackgroundLab\qga')}
$code="if((Get-CimInstance Win32_ComputerSystem).Manufacturer -match 'QEMU'){& 'C:\BackgroundLab\qga\qemu-ga.exe' -m isa-serial -p COM1 -l C:\BackgroundLab\qga.log -a guest-ping,guest-info,guest-sync,guest-exec,guest-exec-status,guest-file-open,guest-file-read,guest-file-close}"
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
$action=New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $encoded"
Register-ScheduledTask -TaskName BcuQemuAgent -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) -User SYSTEM -RunLevel Highest -Force|Out-Null
@{uuid=(Get-CimInstance Win32_ComputerSystemProduct).UUID;computer=$env:COMPUTERNAME;prepared=$true}|ConvertTo-Json|Set-Content C:\BackgroundLab\comparison-identity.json
