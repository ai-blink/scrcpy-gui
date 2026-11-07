param([string]$Output='C:\BackgroundLab\inventory.json')
$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'VMware guest only'}
[ordered]@{
 manufacturer=(Get-CimInstance Win32_ComputerSystem).Manufacturer
 user=(Get-CimInstance Win32_ComputerSystem).UserName
 runtimes=@(Get-ChildItem 'C:\Program Files\dotnet\shared' -Directory -Recurse -Depth 1 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
 processes=@(Get-Process explorer -ErrorAction SilentlyContinue | Select-Object Name,SessionId)
} | ConvertTo-Json -Depth 4 | Set-Content $Output
