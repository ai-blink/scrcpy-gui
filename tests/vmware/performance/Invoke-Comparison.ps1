param([switch]$Worker)
$ErrorActionPreference='Stop'
$root=(Resolve-Path "$PSScriptRoot\..\..\..").Path
$lab=Join-Path $root 'work\bcu-app-performance'
if(-not $Worker){
 $engine=(Get-Process -Id $PID).Path
 Start-Process $engine -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-File',('"{0}"' -f $PSCommandPath),'-Worker')|Out-Null
 return
}
$status=[ordered]@{state='running';platform=$null;error=$null;startedUtc=[DateTime]::UtcNow.ToString('o')}
function Save-State {$status|ConvertTo-Json|Set-Content "$lab\worker-status.json"}
Save-State
$vm=$null;$oldDisk=$null;$oldCheckpoint=$null;$oldState=$null;$session=$null;$sampler=$null;$stop=$null;$diskSwapped=$false;$vmwareStarted=$false;$qemuStarted=$false;$old3d=$null
$v='C:\Program Files\VMware\VMware Workstation\vmrun.exe';$vmx=Join-Path $root 'work\vmware-background\Background-Test.vmx'
$secret=Get-Content "$root\work\vmware-background\guest-admin-credentials.json" -Raw|ConvertFrom-Json
$credential=[PSCredential]::new($secret.username,(ConvertTo-SecureString $secret.password -AsPlainText -Force))
$plan=Get-Content "$lab\plan.json" -Raw|ConvertFrom-Json
try {
 if(Get-Process vmware -ErrorAction SilentlyContinue){throw 'Close the VMware GUI before headless benchmarking'}
 $vmxText=[IO.File]::ReadAllText($vmx)
 foreach($required in @('numvcpus = "4"','memsize = "8192"','ethernet0.present = "FALSE"','usb.present = "FALSE"','usb_xhci.present = "FALSE"','isolation.tools.hgfs.disable = "TRUE"','isolation.tools.copy.disable = "TRUE"','isolation.tools.paste.disable = "TRUE"','isolation.tools.dnd.disable = "TRUE"')){if(-not $vmxText.Contains($required)){throw "VMware baseline mismatch: $required"}}
 if((& $v list) -contains $vmx){throw 'Preparation VM must be stopped'}
 if($vmxText.Contains('mks.enable3d = "TRUE"')){$old3d='TRUE';[IO.File]::WriteAllText($vmx,$vmxText.Replace('mks.enable3d = "TRUE"','mks.enable3d = "FALSE"'))}elseif($vmxText.Contains('mks.enable3d = "FALSE"')){$old3d='FALSE'}else{throw 'Explicit graphics baseline missing'}
 Import-Module Hyper-V
 $vm=Get-VM -Id '73c28998-944e-4a95-ba07-19729c36db53'
 if($vm.Name -ne 'BCU-Comparison-Windows' -or $vm.ProcessorCount -ne 4 -or $vm.MemoryStartup -ne 8GB -or @(Get-VMNetworkAdapter -VM $vm).Count){throw 'Hyper-V isolation/config mismatch'}
 if(@(Get-VM|Where-Object {$_.State -eq 'Running' -and $_.Id -ne $vm.Id}).Count){throw 'Unrelated Hyper-V VM is running; will not stop it'}
 $oldState=$vm.State;$oldCheckpoint=$vm.AutomaticCheckpointsEnabled
 $drives=@(Get-VMHardDiskDrive -VM $vm);if($drives.Count -ne 1){throw 'Expected one disk'};$oldDisk=$drives[0].Path
 @{disk=$oldDisk;checkpoints=$oldCheckpoint;state=[string]$oldState}|ConvertTo-Json|Set-Content "$lab\hyperv-before.json"
 if($vm.State -eq 'Running'){Stop-VM $vm -Confirm:$false}
 if($vm.State -notin @('Off','Running')){throw 'Unexpected Hyper-V state'}
 Set-VM $vm -AutomaticCheckpointsEnabled $false
 $disk=Join-Path $lab ($plan.diskStem+'.vhdx')
 & fsutil sparse setflag $disk 0 | Out-File "$lab\vhdx-attributes.log"
 if((Get-Item $disk).Attributes -band ([IO.FileAttributes]::SparseFile -bor [IO.FileAttributes]::Compressed -bor [IO.FileAttributes]::Encrypted)){throw 'Unsupported VHDX attributes'}
 # Automatic checkpoints can merge after shutdown. Re-read the live attachment
 # on each bounded attempt; never restore a stale, merged-away AVHDX path.
 for($attempt=0;$attempt -lt 60;$attempt++){
  $drive=Get-VMHardDiskDrive -VM $vm
  $restorePath=$drive.Path
  try{Set-VMHardDiskDrive -VMHardDiskDrive $drive -Path $disk;$oldDisk=$restorePath;$diskSwapped=$true;break}catch{
   if($_.Exception.Message -notmatch '병합|merge'){throw};Start-Sleep -Seconds 3
  }
 }
 if(-not $diskSwapped){throw 'Disk merge did not finish in 180 seconds'}
 foreach($platform in @('qemu','hyperv','vmware')){
  $status.platform=$platform;Save-State
  $out=Join-Path $lab ($plan.outputPrefix+$platform);New-Item -ItemType Directory $out -Force|Out-Null
  $stop=Join-Path $out 'sampler.stop'
  if(Test-Path $stop){throw 'Prior measurement directory exists'}
  $sampler=Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f "$PSScriptRoot\Sample-Resources.ps1"),'-Out',('"{0}"' -f "$out\resources.ndjson"),'-StopFile',('"{0}"' -f $stop))
  Start-Sleep -Seconds 10
  $boot=[Diagnostics.Stopwatch]::StartNew()
  if($platform -eq 'vmware'){
   $running=& $v list;if(@($running|Where-Object {$_ -like '*.vmx'}).Count){throw 'VMware already running'}
   & $v start $vmx nogui;if($LASTEXITCODE){throw 'VMware start failed'}
   $vmwareStarted=$true
   $ready=$false
   for($i=0;$i -lt 180;$i++){
    $null=& $v -gu $secret.username -gp $secret.password CopyFileFromGuestToHost $vmx "C:\BackgroundLab\performance\results\$($plan.batchId)\vmware\summary.json" "$out\summary.json" 2>$null
    if($LASTEXITCODE -eq 0){$ready=$true;break};Start-Sleep -Seconds 3
   }
   if(-not $ready){throw 'VMware timeout'}
   & $v stop $vmx soft
   if($LASTEXITCODE){throw 'VMware shutdown failed'};$vmwareStarted=$false
  }elseif($platform -eq 'hyperv'){
   Start-VM $vm|Out-Null
   $deadline=[DateTime]::UtcNow.AddMinutes(3)
   do{try{$session=New-PSSession -VMId $vm.Id -Credential $credential}catch{Start-Sleep -Seconds 3}}until($session -or [DateTime]::UtcNow -gt $deadline)
   if(-not $session){throw 'PowerShell Direct unavailable'}
   $ready=$false
   for($i=0;$i -lt 180;$i++){
    $ready=Invoke-Command -Session $session -ArgumentList $plan.batchId -ScriptBlock {param($b) Test-Path "C:\BackgroundLab\performance\results\$b\hyperv\summary.json"}
    if($ready){break};Start-Sleep -Seconds 3
   }
   if(-not $ready){throw 'Hyper-V timeout'}
   Copy-Item -FromSession $session -LiteralPath "C:\BackgroundLab\performance\results\$($plan.batchId)\hyperv\summary.json" -Destination "$out\summary.json"
   Remove-PSSession $session;$session=$null;Stop-VM $vm -Confirm:$false
  }else{
   & "$PSScriptRoot\..\Start-QemuComparison.ps1" -Lab "$lab\qemu-config"
   if($LASTEXITCODE){throw 'QEMU start failed'}
   $qemuStarted=$true
   & python "$PSScriptRoot\collect_qemu.py" "$lab\qemu-config\config.json" $plan.batchId "$out\summary.json"
   if($LASTEXITCODE){throw 'QEMU collection failed'}
   & python "$PSScriptRoot\..\bcu_qemu.py" shutdown --config "$lab\qemu-config\config.json"
   for($i=0;$i -lt 60 -and (Get-Process qemu-system-x86_64 -ErrorAction SilentlyContinue);$i++){Start-Sleep -Seconds 1}
   if(Get-Process qemu-system-x86_64 -ErrorAction SilentlyContinue){throw 'QEMU shutdown timeout'};$qemuStarted=$false
  }
  @{bootThroughResultAndShutdownSeconds=$boot.Elapsed.TotalSeconds}|ConvertTo-Json|Set-Content "$out\host-timing.json"
  'stop'|Set-Content $stop;$sampler.WaitForExit(10000)|Out-Null;$sampler=$null
  $s=Get-Content "$out\summary.json" -Raw|ConvertFrom-Json
  if($s.batchId -ne $plan.batchId -or $s.platform -ne $platform){throw 'Result identity mismatch'}
  # Preserve failures and continue measuring other candidates.
 }
 $status.state='complete'
}catch{$status.state='failed';$status.error=$_.Exception.Message;$status.detail=$_.ScriptStackTrace}
finally{
 if($stop){'stop'|Set-Content $stop}
 if($sampler){$sampler.WaitForExit(10000)|Out-Null}
 if($session){Remove-PSSession $session}
 if($vmwareStarted){& $v stop $vmx soft}
 if($qemuStarted){& python "$PSScriptRoot\..\bcu_qemu.py" shutdown --config "$lab\qemu-config\config.json"}
 if($old3d -eq 'TRUE' -and ((& $v list) -notcontains $vmx)){[IO.File]::WriteAllText($vmx,[IO.File]::ReadAllText($vmx).Replace('mks.enable3d = "FALSE"','mks.enable3d = "TRUE"'))}
 try{if($vm -and $oldDisk){if((Get-VM -Id $vm.Id).State -eq 'Running'){Stop-VM $vm -Confirm:$false};if($diskSwapped){Get-VMHardDiskDrive -VM $vm|Set-VMHardDiskDrive -Path $oldDisk};Set-VM $vm -AutomaticCheckpointsEnabled $oldCheckpoint;if($oldState -eq 'Running'){Start-VM $vm|Out-Null}}}catch{$status.restoreError=$_.Exception.Message}
 $status.completedUtc=[DateTime]::UtcNow.ToString('o');Save-State
}
