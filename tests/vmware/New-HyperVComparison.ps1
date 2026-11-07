[CmdletBinding()]
param([string]$DiskPath=(Join-Path $PSScriptRoot '..\..\work\bcu-comparison\hyperv\windows.vhdx'),[string]$Name='BCU-Comparison-Windows',[switch]$Start)
$ErrorActionPreference='Stop'
Import-Module Hyper-V -ErrorAction Stop
$DiskPath=(Resolve-Path -LiteralPath $DiskPath).Path
$unsupported=[IO.FileAttributes]::SparseFile -bor [IO.FileAttributes]::Compressed -bor [IO.FileAttributes]::Encrypted
if((Get-Item -LiteralPath $DiskPath).Attributes -band $unsupported){throw 'Hyper-V disk has SparseFile, Compressed or Encrypted attributes. Repair the stopped test disk before creating the VM.'}
if(Get-VM -Name $Name -ErrorAction SilentlyContinue){throw 'A VM with this name exists; it will not be modified'}
# Generation 1 matches the prepared Windows image's BIOS/MBR boot, not a fresh Windows installation.
$vm=New-VM -Name $Name -Generation 1 -MemoryStartupBytes 8GB -VHDPath $DiskPath
Set-VMProcessor -VM $vm -Count 4
Set-VMMemory -VM $vm -DynamicMemoryEnabled $false
Get-VMNetworkAdapter -VM $vm|Remove-VMNetworkAdapter
Disable-VMIntegrationService -VM $vm -Name 'Guest Service Interface' -ErrorAction SilentlyContinue
if($Start){Start-VM -VM $vm}
Get-VM -Id $vm.Id|Select-Object Id,Name,State,Generation,ProcessorCount,MemoryStartup
