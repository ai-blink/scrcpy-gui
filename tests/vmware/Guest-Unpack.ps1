$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'VMware guest only'}
$media=Get-Volume | Where-Object FileSystemLabel -eq 'BACKGROUND_TEST' | Select-Object -First 1
if(-not $media.DriveLetter){throw 'Read-only BACKGROUND_TEST media not mounted'}
$drive=$media.DriveLetter+':\'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $drive 'payload.zip'),'C:\BackgroundLab\payload')
Copy-Item (Join-Path $drive 'Guest-Run.ps1') C:\BackgroundLab\payload\tools\Guest-Run.ps1 -Force
Copy-Item (Join-Path $drive 'Guest-Probe.ps1') C:\BackgroundLab\payload\tools\Guest-Probe.ps1 -Force
Copy-Item (Join-Path $drive 'BackgroundTestDesktop.cs') C:\BackgroundLab\payload\tools\BackgroundTestDesktop.cs -Force
@{ok=$true;media=$media.FileSystemLabel;user=(Get-CimInstance Win32_ComputerSystem).UserName;files=@(Get-ChildItem C:\BackgroundLab\payload -File -Recurse).Count}|ConvertTo-Json|Set-Content C:\BackgroundLab\unpack.json
