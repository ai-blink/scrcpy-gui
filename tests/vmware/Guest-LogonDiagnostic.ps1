$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'VM only'}
$path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$settings=Get-ItemProperty $path
@{auto=$settings.AutoAdminLogon;user=$settings.DefaultUserName;domain=$settings.DefaultDomainName;hasPassword=($null -ne $settings.DefaultPassword);boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime;users=@(Get-LocalUser|Select-Object Name,Enabled);providers=@(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers'|Select-Object -ExpandProperty PSChildName)}|ConvertTo-Json -Depth 5|Set-Content C:\BackgroundLab\logon-diagnostic.json
