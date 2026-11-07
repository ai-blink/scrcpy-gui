$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'VMware guest only'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory('C:\BackgroundLab\source-snapshot.zip','C:\ai\projects')
$map=@{
 'key-demo-osk'='C:\ai\projects\key-demo-osk\osk.tests\bin\Debug\net9.0-windows'
 'new-alt-core'='C:\ai\projects\new-alt\next\tests\AltController.Next.Core.Tests\bin\Debug\net9.0'
 'new-alt-app'='C:\ai\projects\new-alt\next\tests\AltController.Next.App.Tests\bin\Debug\net9.0-windows'
}
foreach($name in $map.Keys){
 New-Item -ItemType Directory $map[$name] -Force|Out-Null
 Copy-Item "C:\BackgroundLab\payload\tests\$name\*" $map[$name] -Recurse -Force
}
$source='C:\BackgroundLab\payload\apps\new-alt\Assets\BackgroundRemoval\isnet_fp16.onnx'
$destination='C:\ai\projects\new-alt\next\src\AltController.Next.App\Assets\BackgroundRemoval\isnet_fp16.onnx'
Copy-Item $source $destination -Force
@{ok=$true;sourceLayout='C:\ai\projects';hostFoldersShared=$false}|ConvertTo-Json|Set-Content C:\BackgroundLab\source-layout.json
