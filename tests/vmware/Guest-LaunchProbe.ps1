param([string]$RunId='manual',[ValidateSet('Probe','Tests','Resolution')][string]$Mode='Probe',[string]$TestFilter='')
$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'VMware guest only'}
if($RunId -notmatch '^[A-Za-z0-9-]+$'){throw 'Invalid run identifier'}
$script=if($Mode -eq 'Tests'){'Guest-Run.ps1'}elseif($Mode -eq 'Resolution'){'Guest-Resolution.ps1'}else{'Guest-Probe.ps1'}
$arguments="-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\BackgroundLab\payload\tools\$script"
if($Mode -ne 'Resolution'){$arguments+=" -RunId $RunId"}
if($TestFilter){if($TestFilter -notmatch '^[A-Za-z0-9_.~|=!-]+$'){throw 'Invalid test filter'};$arguments+=' -TestFilter "'+$TestFilter+'"'}
$action=New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument $arguments
$principal=New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\TestAgent" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "BackgroundLab$Mode" -Action $action -Principal $principal -Force|Out-Null
Start-ScheduledTask -TaskName "BackgroundLab$Mode"
