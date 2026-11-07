param([Parameter(Mandatory)][string]$BatchId)
$ErrorActionPreference='Stop'
$uuid=[Guid](Get-CimInstance Win32_ComputerSystemProduct).UUID
$platform=switch($uuid.ToString()){'71ec4d56-b8a9-a48c-92e8-e83ee248ec83'{'vmware'}'2e903a40-dd97-4884-9c93-b7aeabf338fe'{'hyperv'}'1260f534-5b49-4d00-ae8a-aa12be5987ec'{'qemu'}default{throw 'Not a benchmark VM'}}
if($BatchId -notmatch '^[a-f0-9]{32}$'){throw 'Invalid batch'}
$out="C:\BackgroundLab\performance\results\$BatchId\$platform"
New-Item -ItemType Directory $out -Force|Out-Null
if(Test-Path "$out\summary.json"){exit 0}
$report=[ordered]@{batchId=$BatchId;platform=$platform;uuid=$uuid.ToString();state='running';rounds=@();machine=$null}
try {
 if($platform -ne 'vmware'){
  # VMware Tools is not the management channel on Hyper-V/QEMU. Its startup
  # process can crash on foreign virtual hardware and obscure the test apps.
  Stop-Service VMTools -Force -ErrorAction SilentlyContinue
  Get-Process vmtoolsd -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
 }
 $cs=Get-CimInstance Win32_ComputerSystem
 $report.machine=@{processors=$cs.NumberOfLogicalProcessors;memory=$cs.TotalPhysicalMemory;os=(Get-CimInstance Win32_OperatingSystem).Version}
 if($cs.NumberOfLogicalProcessors -ne 4 -or [Math]::Abs($cs.TotalPhysicalMemory-8GB) -gt 128MB){throw 'CPU/RAM mismatch'}
 # One unscored warm-up, then three identical measured application workflows.
 foreach($round in 0..3){
  $id=[Guid]::NewGuid().ToString('N')
  $clock=[Diagnostics.Stopwatch]::StartNew()
  $p=Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File C:\BackgroundLab\performance\Guest-AppPerf.ps1 -RunId $id -Mode Exercise -ExpectedUuid $uuid -Measure"
  if(-not $p.WaitForExit(240000)){$p.Kill();throw 'App round timed out'}
  $s=Get-Content "C:\BackgroundLab\app-ui\$id\summary.json" -Raw|ConvertFrom-Json
  $pass=$s.status -eq 'complete' -and @($s.apps|Where-Object status -ne 'exercised').Count -eq 0 -and $s.receipts.Count -eq 10 -and @($s.receipts|Where-Object pass -ne $true).Count -eq 0
  $report.rounds+=@{round=$round;warmup=($round -eq 0);passed=$pass;elapsedSeconds=$clock.Elapsed.TotalSeconds;result=$s}
  $report|ConvertTo-Json -Depth 12|Set-Content "$out\progress.json" -Encoding utf8
  if(-not $pass){throw "Acceptance failed in round $round"}
 }
 $report.state='complete'
}catch{$report.state='failed';$report.error=$_.Exception.Message}finally{$report|ConvertTo-Json -Depth 12|Set-Content "$out\summary.json" -Encoding utf8}
