[CmdletBinding()]
param([string]$Lab=(Join-Path $PSScriptRoot '..\..\work\bcu-comparison\qemu'))
$ErrorActionPreference='Stop';$Lab=(Resolve-Path $Lab).Path
$exe='C:\ai\projects\yubikey\work\vm-lab-20261101\qemu\qemu-system-x86_64.exe'
if(Get-CimInstance Win32_Process -Filter "Name = 'qemu-system-x86_64.exe'"|Where-Object {$_.CommandLine -like "*$Lab*windows.qcow2*"}){throw 'This QEMU clone is already running'}
$configPath=Join-Path $Lab 'config.json'
if(Test-Path $configPath){$config=Get-Content $configPath -Raw|ConvertFrom-Json}else{
 function Free-Port {$s=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$s.Start();$p=$s.LocalEndpoint.Port;$s.Stop();return $p}
 $config=@{name='BCU-QEMU-Windows';uuid=[Guid]::NewGuid().ToString();qmp_port=(Free-Port);agent_port=(Free-Port);disk=(Join-Path $Lab 'windows.qcow2');acceleration='whpx';network='none';display='none'}
 $config|ConvertTo-Json|Set-Content $configPath -Encoding utf8
}
$arguments=@('-name',$config.name,'-uuid',$config.uuid,'-accel','whpx','-machine','q35','-cpu','max','-smp','4','-m','8192','-display','none','-monitor','none','-nic','none','-vga','std','-smbios','type=1,manufacturer=QEMU,product=BCUComparison','-drive',"file=$($config.disk),format=qcow2,if=ide,index=0",'-qmp',"tcp:127.0.0.1:$($config.qmp_port),server=on,wait=off",'-chardev',"socket,id=qga,host=127.0.0.1,port=$($config.agent_port),server=on,wait=off",'-serial','chardev:qga')
$config|Add-Member -NotePropertyName executable -NotePropertyValue $exe -Force
$config|Add-Member -NotePropertyName arguments -NotePropertyValue $arguments -Force
$config|ConvertTo-Json -Depth 5|Set-Content $configPath -Encoding utf8
& python (Join-Path $PSScriptRoot 'bcu_qemu.py') start --config $configPath
if($LASTEXITCODE){throw 'Headless QEMU startup failed'}
