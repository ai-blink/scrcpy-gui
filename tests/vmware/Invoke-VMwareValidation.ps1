[CmdletBinding()]
param(
 [string]$VmPath=(Join-Path $PSScriptRoot '..\..\work\vmware-background\Background-Test.vmx'),
 [string]$CredentialFile=(Join-Path $PSScriptRoot '..\..\work\vmware-background\guest-credentials.json'),
 [string]$AdminCredentialFile=(Join-Path $PSScriptRoot '..\..\work\vmware-background\guest-admin-credentials.json'),
 [string]$TestFilter='',
 [int]$TimeoutSeconds=900
)
$ErrorActionPreference='Stop'
$vmrun='C:\Program Files\VMware\VMware Workstation\vmrun.exe'
$VmPath=(Resolve-Path -LiteralPath $VmPath).Path
$lab=Split-Path $VmPath;$evidence=Join-Path $lab ('evidence-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory $evidence -Force|Out-Null
$vmx=Get-Content -LiteralPath $VmPath -Raw
foreach($setting in @('usb.present = "FALSE"','usb_xhci.present = "FALSE"','isolation.tools.copy.disable = "TRUE"','isolation.tools.paste.disable = "TRUE"','isolation.tools.dnd.disable = "TRUE"','isolation.tools.hgfs.disable = "TRUE"','ethernet0.present = "FALSE"')){
 if(-not $vmx.Contains($setting)){throw "Missing isolation setting: $setting"}
}
if(Get-Process vmware -ErrorAction SilentlyContinue){throw 'Close the VMware GUI console before unattended validation'}
$credential=Get-Content -LiteralPath $CredentialFile -Raw|ConvertFrom-Json
$admin=Get-Content -LiteralPath $AdminCredentialFile -Raw|ConvertFrom-Json
$running=& $vmrun list
if($running -notcontains $VmPath){
 & $vmrun -T ws start $VmPath nogui
 if($LASTEXITCODE){throw 'Headless VM startup failed'}
}
$ready=$false
for($attempt=0;$attempt -lt 30;$attempt++){
 $processes=& $vmrun -gu $admin.username -gp $admin.password listProcessesInGuest $VmPath 2>$null
 if($LASTEXITCODE -eq 0 -and $processes -match 'owner=.*\\TestAgent, cmd=explorer.exe'){$ready=$true;break}
 Start-Sleep -Seconds 2
}
if(-not $ready){throw 'The isolated TestAgent desktop did not become ready'}
& $vmrun -gu $admin.username -gp $admin.password runProgramInGuest $VmPath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File 'C:\BackgroundLab\payload\tools\Guest-LaunchProbe.ps1' -Mode Resolution
if($LASTEXITCODE){throw 'Guest display preparation task failed'}
function Guest([string[]]$Arguments){
 & $vmrun -gu $credential.username -gp $credential.password @Arguments
 if($LASTEXITCODE){throw "VMware operation failed: $($Arguments[0]) ($LASTEXITCODE)"}
}
# Read-only host observation. No host input or window activation API exists here.
if(-not ('HostInputObservation' -as [type])){Add-Type @'
using System; using System.Runtime.InteropServices;
public static class HostInputObservation {
 [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point p);
 public static string Cursor(){Point p;GetCursorPos(out p);return p.X+","+p.Y;}
 public static uint ForegroundPid(){uint p;GetWindowThreadProcessId(GetForegroundWindow(),out p);return p;}
}
'@}
$runId=[Guid]::NewGuid().ToString('N')
$beforeCursor=[HostInputObservation]::Cursor();$beforePid=[HostInputObservation]::ForegroundPid()
$admin=Get-Content -LiteralPath $AdminCredentialFile -Raw|ConvertFrom-Json
$launchArguments=@('runProgramInGuest',$VmPath,'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File','C:\BackgroundLab\payload\tools\Guest-LaunchProbe.ps1','-RunId',$runId,'-Mode','Tests')
if($TestFilter){$launchArguments+=@('-TestFilter',$TestFilter)}
& $vmrun -gu $admin.username -gp $admin.password @launchArguments
if($LASTEXITCODE){throw 'Could not start guest test task'}
$watch=[Diagnostics.Stopwatch]::StartNew();$nextPoll=8;$samples=0;$vmForeground=0;$changes=0;$last=$beforeCursor;$summary=$null
while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds){
 $samples++;$point=[HostInputObservation]::Cursor();if($point -ne $last){$changes++;$last=$point}
 $foreground=[HostInputObservation]::ForegroundPid()
 $process=Get-Process -Id $foreground -ErrorAction SilentlyContinue
 if($process.ProcessName -in @('vmware','vmware-vmx')){$vmForeground++}
 if($watch.Elapsed.TotalSeconds -ge $nextPoll){
  $nextPoll=$watch.Elapsed.TotalSeconds+12
  $copyOutput=& $vmrun -gu $admin.username -gp $admin.password CopyFileFromGuestToHost $VmPath 'C:\BackgroundLab\payload\results\summary.json' (Join-Path $evidence 'summary.json') 2>$null
  if($LASTEXITCODE -eq 0){$summary=Get-Content (Join-Path $evidence 'summary.json') -Raw|ConvertFrom-Json;Write-Output "Guest: $($summary.status), suites: $($summary.tests.Count)";if($summary.runId -eq $runId -and $summary.status -in @('complete','failed')){break}}
 }
 Start-Sleep -Milliseconds 40
}
[ordered]@{hostInputInjectionCalls=0;hostActivationCalls=0;samples=$samples;vmForegroundSamples=$vmForeground;hostCursorBefore=$beforeCursor;hostCursorAfter=[HostInputObservation]::Cursor();hostForegroundPidBefore=$beforePid;hostForegroundPidAfter=[HostInputObservation]::ForegroundPid();cursorChangeSamples=$changes;elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,2);note='Host movement may include user input; sampling does not establish a universal zero-interference guarantee.'}|ConvertTo-Json|Set-Content (Join-Path $evidence 'host-observation.json')
$admin=Get-Content -LiteralPath $AdminCredentialFile -Raw|ConvertFrom-Json
& $vmrun -gu $admin.username -gp $admin.password runProgramInGuest $VmPath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File 'C:\BackgroundLab\payload\tools\Guest-LaunchProbe.ps1' -RunId $runId
if($LASTEXITCODE){throw 'Could not start the elevated guest-only probe task'}
$probeWatch=[Diagnostics.Stopwatch]::StartNew();$nextProbePoll=0;$guestInput=$null
while($probeWatch.Elapsed.TotalSeconds -lt 150){
 $samples++;$point=[HostInputObservation]::Cursor();if($point -ne $last){$changes++;$last=$point}
 $foreground=[HostInputObservation]::ForegroundPid();$process=Get-Process -Id $foreground -ErrorAction SilentlyContinue
 if($process.ProcessName -in @('vmware','vmware-vmx')){$vmForeground++}
 if($probeWatch.Elapsed.TotalSeconds -ge $nextProbePoll){
  $nextProbePoll=$probeWatch.Elapsed.TotalSeconds+4
  $copyOutput=& $vmrun -gu $admin.username -gp $admin.password CopyFileFromGuestToHost $VmPath "C:\BackgroundLab\payload\results\$runId\guest-input.json" (Join-Path $evidence 'guest-input.json') 2>$null
  if($LASTEXITCODE -eq 0){$guestInput=Get-Content (Join-Path $evidence 'guest-input.json') -Raw|ConvertFrom-Json;break}
 }
 Start-Sleep -Milliseconds 40
}
[ordered]@{hostInputInjectionCalls=0;hostActivationCalls=0;samples=$samples;vmForegroundSamples=$vmForeground;hostCursorBefore=$beforeCursor;hostCursorAfter=[HostInputObservation]::Cursor();hostForegroundPidBefore=$beforePid;hostForegroundPidAfter=[HostInputObservation]::ForegroundPid();cursorChangeSamples=$changes;elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,2);includesGuestInputProbe=$true;note='Host cursor may move through user input. Sampling is bounded evidence, not a universal zero-interference guarantee.'}|ConvertTo-Json|Set-Content (Join-Path $evidence 'host-observation.json')
foreach($name in @('guest-input.json','apps.json','probe.log','probe-stage.txt','scrcpy-gui.log','key-demo-osk.log','new-alt-core.log','new-alt-app.log','scrcpy-gui.png','key-demo-osk.png','new-alt.png')){
 $copyOutput=& $vmrun -gu $admin.username -gp $admin.password CopyFileFromGuestToHost $VmPath "C:\BackgroundLab\payload\results\$runId\$name" (Join-Path $evidence $name) 2>$null
}
Write-Output "Evidence: $evidence"
$apps=if(Test-Path (Join-Path $evidence 'apps.json')){@(Get-Content (Join-Path $evidence 'apps.json') -Raw|ConvertFrom-Json)}else{@()}
$badApps=@($apps|Where-Object {$_.error -or -not $_.alive -or -not $_.responding -or $_.visibleWindows -lt 1})
if(-not $summary -or $summary.status -ne 'complete' -or @($summary.tests|Where-Object exit -ne 0).Count -gt 0 -or -not $guestInput.textAccepted -or $guestInput.dragSelectionLength -lt 1 -or $apps.Count -ne 3 -or $badApps.Count -gt 0 -or $vmForeground -gt 0){exit 1}

