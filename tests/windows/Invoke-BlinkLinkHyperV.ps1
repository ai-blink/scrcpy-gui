param([switch]$Worker)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out=Join-Path $root 'work\pc-blink-setup\hyperv';$status=Join-Path $out 'status.json'
if(!$Worker){$engine=(Get-Process -Id $PID).Path;$child=Start-Process -FilePath $engine -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath),'-Worker');[pscustomobject]@{pid=$child.Id;status=$status};return}
$record=[ordered]@{state='checking';error=$null;vmId=$null;guestUuid=$null;startedUtc=[DateTime]::UtcNow.ToString('o')}
function Save {$record|ConvertTo-Json|Set-Content -LiteralPath $status -Encoding utf8}
$session=$null;Save
try{
 Import-Module Hyper-V -ErrorAction Stop
 $lab=Join-Path $root 'work\bcu-comparison\hyperv';$pin=Get-Content -LiteralPath (Join-Path $lab 'identity.json') -Raw|ConvertFrom-Json
 $vm=Get-VM -Name 'BCU-Comparison-Windows'
 if($vm.Id -ne [Guid]$pin.vmId){throw 'Pinned VM identity mismatch'}
 if(@(Get-VMNetworkAdapter -VM $vm).Count -ne 0){throw 'Isolated GUI VM must have no network adapters'}
 $disks=@(Get-VMHardDiskDrive -VM $vm);if($disks.Count -ne 1){throw 'Unexpected VM disk count'}
 $leaf=$disks[0].Path;$seen=@{}
 while($leaf){$resolved=(Resolve-Path -LiteralPath $leaf).Path;if(!$resolved.StartsWith($lab+'\',[StringComparison]::OrdinalIgnoreCase) -or $seen.ContainsKey($resolved) -or $seen.Count -ge 32){throw 'Disk chain leaves isolated lab'};$seen[$resolved]=$true;$vhd=Get-VHD -Path $resolved;if(!$vhd.ParentPath){if($resolved -ne [IO.Path]::GetFullPath($pin.disk)){throw 'Base disk mismatch'};break};$leaf=$vhd.ParentPath}
 $record.vmId=$vm.Id.ToString();$record.state='connecting';Save
 if($vm.State -eq 'Off'){Start-VM -VM $vm|Out-Null}elseif($vm.State -ne 'Running'){throw 'Unexpected VM state'}
 $secret=Get-Content -LiteralPath (Join-Path $root 'work\vmware-background\guest-admin-credentials.json') -Raw|ConvertFrom-Json
 $credential=[PSCredential]::new($secret.username,(ConvertTo-SecureString $secret.password -AsPlainText -Force))
 $deadline=[DateTime]::UtcNow.AddMinutes(3)
 do{try{$session=New-PSSession -VMId $vm.Id -Credential $credential -ErrorAction Stop}catch{Start-Sleep -Seconds 2}}until($session -or [DateTime]::UtcNow -ge $deadline)
 if(!$session){throw 'PowerShell Direct unavailable; no host GUI fallback'}
 $uuid=Invoke-Command -Session $session -ScriptBlock {(Get-CimInstance Win32_ComputerSystemProduct).UUID}
 if([Guid]$uuid -ne [Guid]$pin.guestUuid){throw 'Pinned guest UUID mismatch'}
 $record.guestUuid=$uuid;$record.state='waiting-payload';Save
 $ready=Join-Path $out 'payload-ready.json';$deadline=[DateTime]::UtcNow.AddMinutes(10)
 while(!(Test-Path -LiteralPath $ready)){if([DateTime]::UtcNow -gt $deadline){throw 'Payload readiness timeout'};Start-Sleep -Seconds 2}
 $payload=Get-Content -LiteralPath $ready -Raw|ConvertFrom-Json;if($payload.runId -notmatch '^[a-f0-9]{32}$'){throw 'Invalid run ID'}
 $runId=$payload.runId;$guest="C:\BackgroundLab\blinklink-$runId"
 Invoke-Command -Session $session -ArgumentList $guest,$uuid -ScriptBlock {param($d,$expected) if([Guid](Get-CimInstance Win32_ComputerSystemProduct).UUID -ne [Guid]$expected){throw 'Guest identity changed'};New-Item -ItemType Directory -Path $d -Force|Out-Null;Set-Content -LiteralPath "$d\verified-hyperv.txt" -Value $expected}
 Copy-Item -LiteralPath (Join-Path $out 'payload\RemoteControls.Tests.exe') -Destination "$guest\RemoteControls.Tests.exe" -ToSession $session
 $record.state='testing';Save
 Invoke-Command -Session $session -ArgumentList $guest,$runId -ScriptBlock {
  param($d,$nonce)
  if(!(Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue|Where-Object UserName -Match '\\TestAgent$')){throw 'Dedicated TestAgent desktop is not available'}
  $action=New-ScheduledTaskAction -Execute "$d\RemoteControls.Tests.exe" -Argument '--blink-setup-ui' -WorkingDirectory $d
  $principal=New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\TestAgent" -LogonType Interactive -RunLevel Highest
  $task='BlinkLinkSetupUi-'+$nonce;Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Force|Out-Null;Start-ScheduledTask -TaskName $task
 }
 $deadline=[DateTime]::UtcNow.AddMinutes(3);$done=$false
 do{$done=Invoke-Command -Session $session -ArgumentList $guest -ScriptBlock {param($d) Test-Path -LiteralPath "$d\blink-ui-result.json"};if(!$done){Start-Sleep -Seconds 2}}until($done -or [DateTime]::UtcNow -ge $deadline)
 if(!$done){throw 'Guest UI acceptance timed out'}
 foreach($file in @('blink-ui-result.json')){Copy-Item -LiteralPath "$guest\$file" -Destination (Join-Path $out $file) -FromSession $session}
 $result=Get-Content -LiteralPath (Join-Path $out 'blink-ui-result.json') -Raw|ConvertFrom-Json;if(!$result.passed){throw ('Guest UI failed: '+$result.error)}
 Invoke-Command -Session $session -ArgumentList $runId -ScriptBlock {param($nonce) Unregister-ScheduledTask -TaskName ('BlinkLinkSetupUi-'+$nonce) -Confirm:$false}
 foreach($file in @('blink-main.png','blink-dialog.png')){Copy-Item -LiteralPath "$guest\$file" -Destination (Join-Path $out $file) -FromSession $session}
 $record.state='complete';Save
}catch{$record.state='failed';$record.error=$_.Exception.Message;Save}finally{if($session){Remove-PSSession $session}}
