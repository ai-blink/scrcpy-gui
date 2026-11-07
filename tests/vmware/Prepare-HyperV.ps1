[CmdletBinding()]
param([switch]$EnableFeatures,[string]$OutputPath=(Join-Path $PSScriptRoot '..\..\work\bcu-comparison\hyperv-preparation.json'))
$ErrorActionPreference='Stop'
$isAdmin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){throw 'Open an administrator PowerShell to inspect or enable Hyper-V. This script never reboots the host.'}
$features=@();$restart=$false
foreach($name in @('Microsoft-Hyper-V-All','HypervisorPlatform')){
 $feature=Get-WindowsOptionalFeature -Online -FeatureName $name
 if($EnableFeatures -and $feature.State -ne 'Enabled'){$result=Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart;$restart=$restart -or $result.RestartNeeded;$feature=Get-WindowsOptionalFeature -Online -FeatureName $name}
 $features+=@{name=$name;state=$feature.State.ToString()}
}
New-Item -ItemType Directory (Split-Path $OutputPath) -Force|Out-Null
@{features=$features;restartNeeded=$restart;automaticReboot=$false;enableRequested=[bool]$EnableFeatures;timeUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 4|Set-Content $OutputPath -Encoding utf8
Get-Content $OutputPath
