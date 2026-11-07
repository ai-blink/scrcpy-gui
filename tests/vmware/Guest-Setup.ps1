$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'VMware guest only'}
$credential=Get-Content C:\BackgroundLab\guest-credentials.json -Raw|ConvertFrom-Json
if(-not(Get-LocalUser $credential.username -ErrorAction SilentlyContinue)) { New-LocalUser -Name $credential.username -Password (ConvertTo-SecureString $credential.password -AsPlainText -Force) -PasswordNeverExpires | Out-Null }
$users=Get-LocalGroup -SID 'S-1-5-32-545'; Add-LocalGroupMember -Group $users -Member $credential.username -ErrorAction SilentlyContinue
$winlogon='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Remove-ItemProperty $winlogon AutoLogonCount -ErrorAction SilentlyContinue
Set-ItemProperty $winlogon AutoAdminLogon '1'
Set-ItemProperty $winlogon DefaultUserName $credential.username
Set-ItemProperty $winlogon DefaultPassword $credential.password
Set-ItemProperty $winlogon DefaultDomainName $env:COMPUTERNAME
# Permissions apply inside the disposable clone only.
icacls.exe C:\BackgroundLab /grant '*S-1-5-32-545:(OI)(CI)M' /T /Q | Out-Null
@{ok=$true;account=$credential.username;vmOnly=$true} | ConvertTo-Json | Set-Content C:\BackgroundLab\setup.json

