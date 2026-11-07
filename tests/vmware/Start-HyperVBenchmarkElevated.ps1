[CmdletBinding()]
param([switch]$Worker,[switch]$DiagnoseDrag)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$statusPath=Join-Path $root 'work\bcu-comparison\hyperv\benchmark-elevated-status.json'
if(-not $Worker){
 # Explicit user consent is required before invoking this entry point: UAC takes focus.
 $engine=(Get-Process -Id $PID).Path
 $child=Start-Process -FilePath $engine -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-File',('"{0}"' -f $PSCommandPath),'-Worker',$(if($DiagnoseDrag){'-DiagnoseDrag'}else{''}))
 [pscustomobject]@{pid=$child.Id;statusPath=$statusPath}
 return
}
$admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Elevated worker required'}
$record=[ordered]@{state='running';startedUtc=[DateTime]::UtcNow.ToString('o');completedUtc=$null;error=$null}
$record|ConvertTo-Json|Set-Content -LiteralPath $statusPath -Encoding utf8
try{
 if(Get-Process qemu-system-x86_64 -ErrorAction SilentlyContinue){throw 'QEMU still running; benchmark overlap refused'}
 if($DiagnoseDrag){try{& (Join-Path $PSScriptRoot 'Invoke-HyperVPreflight20.ps1') -Benchmark -LegacyDrag}catch{Write-Warning $_.Exception.Message}}
 & (Join-Path $PSScriptRoot 'Invoke-HyperVPreflight20.ps1') -Benchmark
 $record.state='complete'
}catch{
 $record.state='failed';$record.error=$_.Exception.Message
 throw
}finally{
 $record.completedUtc=[DateTime]::UtcNow.ToString('o')
 $record|ConvertTo-Json|Set-Content -LiteralPath $statusPath -Encoding utf8
}
