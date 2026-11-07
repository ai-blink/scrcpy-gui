param([switch]$Benchmark,[string]$DiskPath='')
$ErrorActionPreference='Stop'
$lab=(Resolve-Path (Join-Path $PSScriptRoot '..\..\work\bcu-comparison\qemu')).Path
$configPath=Join-Path $lab 'config.json';$config=Get-Content $configPath -Raw|ConvertFrom-Json
$staged=Get-Content (Join-Path $lab 'staged-run.json') -Raw|ConvertFrom-Json
if([Guid]$staged.expectedUuid -ne [Guid]$config.uuid){throw 'Staged UUID mismatch'}
$out=Join-Path $lab ('preflight-'+$staged.runId)
if(Test-Path $out){throw 'Evidence directory already exists'}
$disk=if($DiskPath){(Resolve-Path -LiteralPath $DiskPath).Path}else{Join-Path $lab $(if($Benchmark){'windows-benchmark-staged.qcow2'}else{'windows-preflight-staged.qcow2'})}
if(-not $disk.StartsWith($lab+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Staged disk must be inside the QEMU comparison directory'}
if(-not(Test-Path $disk)){throw 'Staged disk missing'}
if(Get-Process qemu-system-x86_64 -ErrorAction SilentlyContinue){throw 'QEMU is already running'}
Copy-Item $configPath (Join-Path $lab ('config-before-'+$staged.runId+'.json'))
$config.disk=$disk;$config|ConvertTo-Json -Depth 6|Set-Content $configPath -Encoding utf8
New-Item -ItemType Directory $out|Out-Null
$stop=Join-Path $out 'observer.stop';$observer=$null;$started=$false
try{
 $observer=Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f (Join-Path $PSScriptRoot 'Observe-Host.ps1')),'-OutputDirectory',('"{0}"' -f $out),'-DurationSeconds','900','-StopFile',('"{0}"' -f $stop))
 for($i=0;$i -lt 50;$i++){if(Test-Path (Join-Path $out 'observer-ready.json')){break};Start-Sleep -Milliseconds 100}
 if(-not(Test-Path (Join-Path $out 'observer-ready.json'))){throw 'Observer unavailable'}
 & (Join-Path $PSScriptRoot 'Start-QemuComparison.ps1') -Lab $lab
 $started=$true
 Push-Location $PSScriptRoot
 try{
  $ready=$false
  for($i=0;$i -lt 36;$i++){
   & python -c 'import sys; from bcu_qemu import Channel; a=Channel(int(sys.argv[1]),timeout=2); a.call("guest-ping"); a.close()' $config.agent_port 2>$null
   if($LASTEXITCODE -eq 0){$ready=$true;break}
   Start-Sleep -Seconds 3
  }
  if(-not $ready){throw 'QGA readiness timeout'}
  $collectOptions=if($Benchmark){@('--expected-count','600')}else{@()}
  & python bcu_qemu.py collect-staged --config $configPath --run-id $staged.runId --out (Join-Path $out 'guest') @collectOptions
  if($LASTEXITCODE){throw 'Staged guest collection failed'}
 }finally{Pop-Location}
}finally{
 'stop'|Set-Content $stop
 if($observer -and -not $observer.HasExited){$observer.WaitForExit(5000)|Out-Null}
 if($started){& python (Join-Path $PSScriptRoot 'bcu_qemu.py') shutdown --config $configPath}
 Write-Output "Evidence: $out"
}
