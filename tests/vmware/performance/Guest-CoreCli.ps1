$ErrorActionPreference='Stop'
if([Guid](Get-CimInstance Win32_ComputerSystemProduct).UUID -ne [Guid]'71ec4d56-b8a9-a48c-92e8-e83ee248ec83'){throw 'Approved guest only'}
$out='C:\BackgroundLab\performance\core-cli-v2';New-Item -ItemType Directory $out -Force|Out-Null
$exe='C:\Program Files\dotnet\dotnet.exe'
$dll='C:\ai\projects\new-alt\next\tests\AltController.Next.Core.Tests\bin\Debug\net9.0\AltController.Next.Core.Tests.dll'
if((Get-FileHash $dll).Hash -ne (Get-FileHash 'C:\BackgroundLab\payload\tests\new-alt-core\AltController.Next.Core.Tests.dll').Hash){throw 'Test binary differs from shared payload'}
$rows=@()
foreach($i in 1..3){
 $clock=[Diagnostics.Stopwatch]::StartNew()
 $p=Start-Process $exe -ArgumentList "vstest $dll /TestCaseFilter:Category!=DesktopUI /ResultsDirectory:$out /Logger:trx;LogFileName=round-$i.trx" -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput "$out\round-$i.log" -RedirectStandardError "$out\round-$i.err"
 if(-not $p.WaitForExit(120000)){$p.Kill();throw 'CLI timeout'}
 [xml]$trx=Get-Content "$out\round-$i.trx"
 $counter=$trx.TestRun.ResultSummary.Counters
 $rows+=@{round=$i;exit=$p.ExitCode;seconds=$clock.Elapsed.TotalSeconds;total=[int]$counter.total;passed=[int]$counter.passed;failed=[int]$counter.failed}
}
@{route='native dotnet vstest; no interactive desktop';session=[Diagnostics.Process]::GetCurrentProcess().SessionId;testAssemblySha256=(Get-FileHash $dll).Hash;scope='new-alt Core backend regression only, not a CLI adapter or GUI acceptance replacement';rounds=$rows}|ConvertTo-Json -Depth 5|Set-Content "$out\summary.json" -Encoding utf8
