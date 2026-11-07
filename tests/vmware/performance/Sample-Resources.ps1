param([Parameter(Mandatory)][string]$Out,[Parameter(Mandatory)][string]$StopFile)
$ErrorActionPreference='Continue'
$logical=(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
Import-Module Hyper-V -ErrorAction SilentlyContinue
$deadline=[DateTime]::UtcNow.AddMinutes(20)
while(-not(Test-Path $StopFile) -and [DateTime]::UtcNow -lt $deadline){
 $row=[ordered]@{utc=[DateTime]::UtcNow.ToString('o');logicalCpu=$logical;host=$null;processes=@();hypervVirtualProcessors=@()}
 try{$row.host=Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"|Select-Object PercentProcessorTime}catch{}
 foreach($p in Get-Process vmware-vmx,qemu-system-x86_64,vmwp -ErrorAction SilentlyContinue){try{$row.processes+=@{pid=$p.Id;name=$p.ProcessName;cpuSeconds=$p.TotalProcessorTime.TotalSeconds;workingSetBytes=$p.WorkingSet64;privateBytes=$p.PrivateMemorySize64}}catch{}}
 try{$row.hypervVirtualProcessors=@(Get-CimInstance Win32_PerfFormattedData_HvStats_HyperVHypervisorVirtualProcessor -ErrorAction Stop|Select-Object Name,PercentGuestRunTime,PercentTotalRunTime)}catch{$row.hypervCounterError=$_.Exception.Message}
 try{$row.hypervVm=Get-VM -Id '73c28998-944e-4a95-ba07-19729c36db53'|Select-Object Name,State,CPUUsage,MemoryAssigned,MemoryDemand}catch{}
 $row|ConvertTo-Json -Depth 5 -Compress|Add-Content $Out -Encoding utf8
 Start-Sleep -Seconds 1
}
