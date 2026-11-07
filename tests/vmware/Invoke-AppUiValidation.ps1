param([ValidateSet('Inspect','Exercise')][string]$Mode='Inspect')
$ErrorActionPreference='Stop'
$lab=(Resolve-Path (Join-Path $PSScriptRoot '..\..\work\vmware-background')).Path
$vmx=Join-Path $lab 'Background-Test.vmx';$v='C:\Program Files\VMware\VMware Workstation\vmrun.exe'
$config=Get-Content $vmx -Raw
foreach($setting in @('usb.present = "FALSE"','usb_xhci.present = "FALSE"','ethernet0.present = "FALSE"','isolation.tools.hgfs.disable = "TRUE"','isolation.tools.copy.disable = "TRUE"','isolation.tools.paste.disable = "TRUE"','isolation.tools.dnd.disable = "TRUE"')){if(-not $config.Contains($setting)){throw "Isolation guard missing: $setting"}}
if(Get-Process vmware -ErrorAction SilentlyContinue){throw 'VMware GUI must be closed'}
$running=& $v list;if($running -notcontains $vmx){& $v -T ws start $vmx nogui;if($LASTEXITCODE){throw 'VM start failed'}}
$cred=Get-Content (Join-Path $lab 'guest-admin-credentials.json') -Raw|ConvertFrom-Json
$runId=[Guid]::NewGuid().ToString('N');$out=Join-Path $lab "app-ui-$runId";New-Item -ItemType Directory $out|Out-Null
& $v -gu $cred.username -gp $cred.password CopyFileFromHostToGuest $vmx (Join-Path $PSScriptRoot 'Guest-AppUi.ps1') C:\BackgroundLab\payload\tools\Guest-AppUi.ps1
if($LASTEXITCODE){throw 'Guest script copy failed'}
$observer=$null;$stop=Join-Path $out 'observer.stop'
try{
 $observer=Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $out 'observer-stderr.log') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f (Join-Path $PSScriptRoot 'Observe-Host.ps1')),'-OutputDirectory',('"{0}"' -f $out),'-DurationSeconds','600','-StopFile',('"{0}"' -f $stop))
 for($i=0;$i -lt 100;$i++){if(Test-Path (Join-Path $out 'observer-ready.json')){break};if($observer.HasExited){throw 'Observer failed'};Start-Sleep -Milliseconds 100}
 if(-not(Test-Path (Join-Path $out 'observer-ready.json'))){throw 'Observer readiness timeout'}
 $code=@"
`$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystemProduct).UUID -ne '71EC4D56-B8A9-A48C-92E8-E83EE248EC83'){throw 'Guest identity mismatch'}
`$a=New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\BackgroundLab\payload\tools\Guest-AppUi.ps1 -RunId $runId -Mode $Mode'
`$p=New-ScheduledTaskPrincipal -UserId "`$env:COMPUTERNAME\TestAgent" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName BcuAppUi -Action `$a -Principal `$p -Force|Out-Null
Start-ScheduledTask -TaskName BcuAppUi
"@
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
 & $v -gu $cred.username -gp $cred.password runProgramInGuest $vmx 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
 if($LASTEXITCODE){throw 'Guest launch failed'}
 $copied=$false
 for($i=0;$i -lt 100;$i++){
  $null=& $v -gu $cred.username -gp $cred.password CopyFileFromGuestToHost $vmx "C:\BackgroundLab\app-ui\$runId.zip" (Join-Path $out 'guest.zip') 2>$null
  if($LASTEXITCODE -eq 0){$copied=$true;break};Start-Sleep -Seconds 2
 }
 if(-not $copied){throw 'Guest result timeout'}
 Expand-Archive -LiteralPath (Join-Path $out 'guest.zip') -DestinationPath (Join-Path $out 'guest')
 $summary=Get-Content (Join-Path $out 'guest\summary.json') -Raw|ConvertFrom-Json
 if($summary.runId -ne $runId -or $summary.guestUuid -ne '71EC4D56-B8A9-A48C-92E8-E83EE248EC83'){throw 'Evidence identity mismatch'}
 $summary|ConvertTo-Json -Depth 8
 if($summary.status -ne 'complete' -or @($summary.apps|Where-Object status -eq 'failed').Count -gt 0 -or @($summary.receipts|Where-Object pass -eq $false).Count -gt 0){throw 'App validation failed; inspect guest summary and screenshots'}
 if($Mode -eq 'Exercise' -and @($summary.receipts).Count -lt 10){throw 'Incomplete app action coverage'}
}finally{
 'stop'|Set-Content $stop
 if($observer -and -not $observer.HasExited){$observer.WaitForExit(5000)|Out-Null}
 Write-Output "Evidence: $out"
}
