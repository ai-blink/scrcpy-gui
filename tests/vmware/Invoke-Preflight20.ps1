[CmdletBinding()]
param([string]$Lab=(Join-Path $PSScriptRoot '..\..\work\vmware-background'),[switch]$Benchmark)
$expectedCount=if($Benchmark){600}else{20}
$ErrorActionPreference='Stop';$Lab=(Resolve-Path $Lab).Path
$vmx=Join-Path $Lab 'Background-Test.vmx';$vmrun='C:\Program Files\VMware\VMware Workstation\vmrun.exe'
$config=Get-Content $vmx -Raw
if(Get-Process vmware -ErrorAction SilentlyContinue){throw 'VMware GUI must be closed'}
foreach($line in @('ethernet0.present = "FALSE"','usb.present = "FALSE"','usb_xhci.present = "FALSE"','isolation.tools.hgfs.disable = "TRUE"','isolation.tools.copy.disable = "TRUE"','isolation.tools.paste.disable = "TRUE"','isolation.tools.dnd.disable = "TRUE"')){if(-not $config.Contains($line)){throw "Isolation guard missing: $line"}}
$uuidMatch=[regex]::Match($config,'(?m)^uuid.bios = "([^"]+)"')
if(-not $uuidMatch.Success){throw 'VM identity missing'}
[byte[]]$uuidBytes=@([regex]::Matches($uuidMatch.Groups[1].Value,'[0-9a-fA-F]{2}')|ForEach-Object {[Convert]::ToByte($_.Value,16)})
$expectedUuid=[Guid]::new($uuidBytes).ToString()
$admin=Get-Content (Join-Path $Lab 'guest-admin-credentials.json') -Raw|ConvertFrom-Json
$runId=[Guid]::NewGuid().ToString('N');$out=Join-Path $Lab "preflight-$runId";New-Item -ItemType Directory $out|Out-Null
$observer=$null;$summary=$null;$stop=Join-Path $out 'observer.stop'
try{
 $launchOptions=if($Benchmark){@('-Benchmark')}else{@()}
 $running=& $vmrun list;if($running -notcontains $vmx){& $vmrun -T ws start $vmx nogui;if($LASTEXITCODE){throw 'VM start failed'}}
 $ready=$false;for($i=0;$i -lt 30;$i++){$processes=& $vmrun -gu $admin.username -gp $admin.password listProcessesInGuest $vmx;if($processes -match 'owner=.*\\TestAgent, cmd=explorer.exe'){$ready=$true;break};Start-Sleep -Seconds 2};if(-not $ready){throw 'Guest desktop unavailable'}
 foreach($name in @('Guest-Preflight20.ps1','Guest-LaunchPreflight.ps1')){& $vmrun -gu $admin.username -gp $admin.password CopyFileFromHostToGuest $vmx (Join-Path $PSScriptRoot $name) "C:\BackgroundLab\payload\tools\$name";if($LASTEXITCODE){throw 'Guest tool copy failed'}}
 $si=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path);$si.UseShellExecute=$false;$si.CreateNoWindow=$true
 foreach($arg in @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Observe-Host.ps1'),'-OutputDirectory',$out,'-DurationSeconds','900','-StopFile',$stop)){$si.ArgumentList.Add($arg)}
 $observer=[Diagnostics.Process]::Start($si)
 for($i=0;$i -lt 50;$i++){if(Test-Path (Join-Path $out 'observer-ready.json')){break};if($observer.HasExited){throw 'Observer startup failed'};Start-Sleep -Milliseconds 100}
 if(-not(Test-Path (Join-Path $out 'observer-ready.json'))){throw 'Observer readiness timeout'}
 $launchCode="Stop-ScheduledTask -TaskName BcuPreflight20 -ErrorAction SilentlyContinue; & 'C:\BackgroundLab\payload\tools\Guest-LaunchPreflight.ps1' -RunId '$runId' -ExpectedUuid '$expectedUuid' $launchOptions"
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($launchCode))
 & $vmrun -gu $admin.username -gp $admin.password runProgramInGuest $vmx 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
 if($LASTEXITCODE){throw 'Guest task launch failed'}
 for($i=0;$i -lt 600;$i++){
  $copy=& $vmrun -gu $admin.username -gp $admin.password CopyFileFromGuestToHost $vmx "C:\BackgroundLab\preflight\$runId\summary.json" (Join-Path $out 'summary.json')
  if($LASTEXITCODE -eq 0){$summary=Get-Content (Join-Path $out 'summary.json') -Raw|ConvertFrom-Json;if($summary.runId -ne $runId -or ([Guid]$summary.actualUuid) -ne ([Guid]$expectedUuid)){throw 'Result nonce or VM identity mismatch'};break}
  Start-Sleep -Seconds 1
 }
 if(-not $summary){throw 'Preflight timeout'}
 & $vmrun -gu $admin.username -gp $admin.password CopyFileFromGuestToHost $vmx "C:\BackgroundLab\preflight\$runId\actions.ndjson" (Join-Path $out 'actions.ndjson')
 if($LASTEXITCODE){throw 'Receipt collection failed'}
}finally{
 'stop'|Set-Content $stop
 if($observer -and -not $observer.HasExited){if(-not $observer.WaitForExit(5000)){$observer.Kill();throw 'Observer did not stop cleanly'}}
 Write-Output "Evidence: $out"
}
Get-Content (Join-Path $out 'summary.json');Get-Content (Join-Path $out 'host-health.json')
if($summary.pass -ne $expectedCount -or $summary.executed -ne $expectedCount){exit 1}
