[CmdletBinding()]
param([string]$Lab=(Join-Path $PSScriptRoot '..\..\work\bcu-comparison\hyperv'),[switch]$Benchmark,[switch]$LegacyDrag)
$expectedCount=if($Benchmark){600}else{20}
$ErrorActionPreference='Stop'
$admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run this script in administrator PowerShell.'}
Import-Module Hyper-V -ErrorAction Stop
$Lab=(Resolve-Path -LiteralPath $Lab).Path
$disk=(Resolve-Path -LiteralPath (Join-Path $Lab 'windows.vhdx')).Path
$unsupported=[IO.FileAttributes]::SparseFile -bor [IO.FileAttributes]::Compressed -bor [IO.FileAttributes]::Encrypted
if((Get-Item -LiteralPath $disk).Attributes -band $unsupported){throw 'Hyper-V disk has SparseFile, Compressed or Encrypted attributes. Repair the stopped test disk before retrying.'}
$name='BCU-Comparison-Windows';$pinPath=Join-Path $Lab 'identity.json'
$vm=Get-VM -Name $name -ErrorAction SilentlyContinue
if($vm){
 if(-not(Test-Path -LiteralPath $pinPath)){throw 'Existing VM has no local identity pin; refusing to modify it.'}
 $pin=Get-Content -LiteralPath $pinPath -Raw|ConvertFrom-Json
 if([Guid]$pin.vmId -ne $vm.Id){throw 'Hyper-V VM identity mismatch'}
}else{
 if(Test-Path -LiteralPath $pinPath){throw 'Pinned VM is missing; inspect identity.json before recreating.'}
 & (Join-Path $PSScriptRoot 'New-HyperVComparison.ps1') -DiskPath $disk -Name $name|Out-Null
 $vm=Get-VM -Name $name
 @{vmId=$vm.Id.ToString();disk=$disk;name=$name}|ConvertTo-Json|Set-Content -LiteralPath $pinPath -Encoding utf8
}
$attached=@(Get-VMHardDiskDrive -VM $vm)
if($attached.Count -ne 1){throw 'Expected exactly one VM disk attachment'}
# Hyper-V may attach an automatic checkpoint AVHDX after the first boot.
# Accept only a bounded, local parent chain terminating at the pinned base disk.
$diskChain=@();$leaf=$attached[0].Path;$seen=@{}
while($true){
 $current=(Resolve-Path -LiteralPath $leaf).Path
 if($seen.ContainsKey($current) -or $diskChain.Count -ge 32){throw 'Invalid or excessive disk parent chain'}
 if(-not $current.StartsWith($Lab+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Disk chain leaves comparison directory: $current"}
 if((Get-Item -LiteralPath $current).Attributes -band $unsupported){throw "Unsupported disk file attributes: $current"}
 $seen[$current]=$true;$diskChain+=$current
 $vhd=Get-VHD -Path $current -ErrorAction Stop
 if($current -eq $disk){
  if($vhd.ParentPath){throw 'Pinned base unexpectedly has a parent disk'}
  break
 }
 if($vhd.VhdType -ne 'Differencing' -or -not $vhd.ParentPath){throw "Disk chain does not reach pinned base: $current"}
 $leaf=$vhd.ParentPath
 if(-not [IO.Path]::IsPathRooted($leaf)){$leaf=Join-Path (Split-Path $current) $leaf}
}
if(@(Get-VMNetworkAdapter -VM $vm).Count -ne 0){throw 'VM must have no network adapters'}
if($vm.Generation -ne 1 -or $vm.ProcessorCount -ne 4 -or $vm.MemoryStartup -ne 8GB){throw 'VM configuration differs from comparison baseline'}
$secretPath=Join-Path $PSScriptRoot '..\..\work\vmware-background\guest-admin-credentials.json'
$secret=Get-Content -LiteralPath $secretPath -Raw|ConvertFrom-Json
$credential=[PSCredential]::new($secret.username,(ConvertTo-SecureString $secret.password -AsPlainText -Force))
$runId=[Guid]::NewGuid().ToString('N');$out=Join-Path $Lab "preflight-$runId"
New-Item -ItemType Directory -Path $out|Out-Null
ConvertTo-Json -InputObject @($diskChain)|Set-Content -LiteralPath (Join-Path $out 'disk-chain.json') -Encoding utf8
$session=$null;$observer=$null;$summary=$null;$stop=Join-Path $out 'observer.stop'
try{
 if($vm.State -eq 'Off'){Start-VM -VM $vm|Out-Null}elseif($vm.State -ne 'Running'){throw "Unexpected VM state: $($vm.State)"}
 $deadline=[DateTime]::UtcNow.AddMinutes(3)
 do{
  try{$session=New-PSSession -VMId $vm.Id -Credential $credential -ErrorAction Stop}catch{Start-Sleep -Seconds 3}
 }until($session -or [DateTime]::UtcNow -ge $deadline)
 if(-not $session){throw 'PowerShell Direct unavailable after 3 minutes; no console/input fallback.'}
 $identity=Invoke-Command -Session $session -ScriptBlock {
  $cs=Get-CimInstance Win32_ComputerSystem;$product=Get-CimInstance Win32_ComputerSystemProduct
  if($cs.Manufacturer -ne 'Microsoft Corporation' -or $cs.Model -ne 'Virtual Machine'){throw 'Unexpected guest platform'}
  [pscustomobject]@{uuid=$product.UUID;manufacturer=$cs.Manufacturer;model=$cs.Model}
 }
 $expectedUuid=([Guid]$identity.uuid).ToString()
 if(Test-Path -LiteralPath $pinPath){
  $pin=Get-Content -LiteralPath $pinPath -Raw|ConvertFrom-Json
  if($pin.guestUuid -and [Guid]$pin.guestUuid -ne [Guid]$expectedUuid){throw 'Pinned guest UUID changed'}
 }
 @{vmId=$vm.Id.ToString();disk=$disk;name=$name;guestUuid=$expectedUuid}|ConvertTo-Json|Set-Content -LiteralPath $pinPath -Encoding utf8
 @{runId=$runId;vmId=$vm.Id.ToString();guestUuid=$expectedUuid;channel='PowerShell Direct';timeUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $out 'run.json') -Encoding utf8
 foreach($tool in @('Guest-Preflight20.ps1','Guest-LaunchPreflight.ps1')){
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $tool) -Destination "C:\BackgroundLab\payload\tools\$tool" -ToSession $session
 }
 $observerScript=Join-Path $PSScriptRoot 'Observe-Host.ps1'
 # Explicit hidden process; Windows PowerShell supports this on an administrator's ordinary console.
 $observer=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $out 'observer-stdout.log') -RedirectStandardError (Join-Path $out 'observer-stderr.log') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $observerScript),'-OutputDirectory',('"{0}"' -f $out),'-DurationSeconds','900','-StopFile',('"{0}"' -f $stop))
 for($i=0;$i -lt 50;$i++){
  if(Test-Path -LiteralPath (Join-Path $out 'observer-ready.json')){break}
  if($observer.HasExited){throw 'Host observer failed to start'}
  Start-Sleep -Milliseconds 100
 }
 if(-not(Test-Path -LiteralPath (Join-Path $out 'observer-ready.json'))){throw 'Host observer readiness timeout'}
 Invoke-Command -Session $session -ArgumentList $runId,$expectedUuid,([bool]$Benchmark),([bool]$LegacyDrag) -ScriptBlock {
  param($nonce,$uuid,$bench,$legacy)
  $launchOptions=@();if($bench){$launchOptions+='-Benchmark'};if($legacy){$launchOptions+='-LegacyDrag'}
  # PS Direct's session policy may prohibit .ps1 files. Limit the override to this
  # guest child process, matching the existing scheduled fixture invocation.
  if($nonce -notmatch '^[a-f0-9]{32}$'){throw 'Invalid nonce'}
  $uuid=([Guid]$uuid).ToString()
  $code="& 'C:\BackgroundLab\payload\tools\Guest-LaunchPreflight.ps1' -RunId '$nonce' -ExpectedUuid '$uuid' $launchOptions"
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
  $messages=& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1
  if($LASTEXITCODE -ne 0){throw "Guest launcher failed: $($messages | Out-String)"}
 }
 for($i=0;$i -lt 600;$i++){
  $ready=Invoke-Command -Session $session -ArgumentList $runId -ScriptBlock {param($nonce) Test-Path -LiteralPath "C:\BackgroundLab\preflight\$nonce\summary.json"}
  if($ready){
   Copy-Item -LiteralPath "C:\BackgroundLab\preflight\$runId\summary.json" -FromSession $session -Destination (Join-Path $out 'summary.json')
   $summary=Get-Content -LiteralPath (Join-Path $out 'summary.json') -Raw|ConvertFrom-Json
   if($summary.runId -ne $runId -or [Guid]$summary.actualUuid -ne [Guid]$expectedUuid){throw 'Result nonce or guest identity mismatch'}
   Copy-Item -LiteralPath "C:\BackgroundLab\preflight\$runId\actions.ndjson" -FromSession $session -Destination (Join-Path $out 'actions.ndjson')
   break
  }
  Start-Sleep -Seconds 1
 }
 if(-not $summary){throw 'Guest interactive preflight timed out; no host input fallback.'}
}catch{
 @{runId=$runId;status='failed';error=$_.Exception.Message}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $out 'failure.json') -Encoding utf8
 throw
}finally{
 'stop'|Set-Content -LiteralPath $stop
 if($observer -and -not $observer.HasExited){if(-not $observer.WaitForExit(5000)){$observer.Kill()}}
 if($session){Remove-PSSession $session}
 Write-Output "Evidence: $out"
}
Get-Content -LiteralPath (Join-Path $out 'summary.json')
Get-Content -LiteralPath (Join-Path $out 'host-health.json')
if($summary.executed -ne $expectedCount -or $summary.pass -ne $expectedCount){throw "Hyper-V completed with failed checks; expected $expectedCount passes. See summary.json and actions.ndjson."}
