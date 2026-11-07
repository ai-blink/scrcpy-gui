param([string]$Root='C:\BackgroundLab\payload',[string]$RunId='manual',[string]$TestFilter='')
$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'VMware guest only'}
if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Interactive guest session required'}
$out=Join-Path "$Root\results" $RunId; New-Item -ItemType Directory $out -Force|Out-Null
$env:DOTNET_ROOT=Join-Path $Root 'dotnet';$env:PATH=$env:DOTNET_ROOT+';'+$env:PATH
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1';$env:DOTNET_NOLOGO='1'
$report=[ordered]@{runId=$RunId;filter=$TestFilter;guest=(Get-CimInstance Win32_ComputerSystem).Manufacturer;session=[Diagnostics.Process]::GetCurrentProcess().SessionId;tests=@();apps=@();status='running'}
function Save-Report {$report|ConvertTo-Json -Depth 8|Set-Content "$Root\results\summary.json" -Encoding utf8}
Save-Report
try {
 Add-Type -Path "$Root\tools\BackgroundTestDesktop.cs"
 $dotnet="$Root\dotnet\dotnet.exe"
 $cases=@(
  @{name='scrcpy-gui';executable="$Root\tests\scrcpy-gui\RemoteControls.Tests.exe";arguments=@('--render')},
  @{name='key-demo-osk';arguments=@('vstest','C:\ai\projects\key-demo-osk\osk.tests\bin\Debug\net9.0-windows\FlowType.OSK.Tests.dll',"/ResultsDirectory:$out\osk",'/Logger:trx')},
  @{name='new-alt-core';arguments=@('vstest','C:\ai\projects\new-alt\next\tests\AltController.Next.Core.Tests\bin\Debug\net9.0\AltController.Next.Core.Tests.dll',"/ResultsDirectory:$out\new-alt-core",'/Logger:trx')},
  @{name='new-alt-app';arguments=@('vstest','C:\ai\projects\new-alt\next\tests\AltController.Next.App.Tests\bin\Debug\net9.0-windows\AltController.Next.App.Tests.dll',"/Settings:$Root\tests\full.runsettings","/ResultsDirectory:$out\new-alt-app",'/Logger:trx')}
 )
 if($TestFilter){$cases=@($cases|Where-Object name -eq 'new-alt-app');$cases[0].arguments+=('/TestCaseFilter:'+$TestFilter)}
 foreach($case in $cases){
  $before=[BackgroundTestDesktop]::InputDesktopName();$session=$null;$peak=0;$clock=[Diagnostics.Stopwatch]::StartNew()
  try {
   $exe=if($case.executable){$case.executable}else{$dotnet}
   $session=[BackgroundTestDesktop]::Start($exe,[string[]]$case.arguments,$Root,"$out\$($case.name).log")
   while(-not $session.Wait(250)){$peak=[Math]::Max($peak,$session.WindowCount);if($clock.Elapsed.TotalSeconds -gt 360){throw 'Test timeout'}}
   $report.tests+=@{name=$case.name;exit=[int]$session.ExitCode;elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,2);peakWindows=$peak;desktop=$session.DesktopName;inputBefore=$before;inputAfter=[BackgroundTestDesktop]::InputDesktopName()}
  }catch{$report.tests+=@{name=$case.name;error=$_.Exception.Message;exit=-1}}finally{if($session){$session.Dispose()}}
  Save-Report
 }
 $report.status='complete'
}catch{$report.status='failed';$report.error=$_.Exception.Message}finally{Save-Report}
