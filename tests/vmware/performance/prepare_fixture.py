"""Derive an instrumented copy without changing the established acceptance fixture."""
from pathlib import Path
import hashlib, json
root=Path(__file__).resolve().parent
source=root.parent/'Guest-AppUi.ps1'
s=source.read_text(encoding='utf-8-sig')
s=s.replace("[string]$Mode='Inspect')", "[string]$Mode='Inspect',[Parameter(Mandatory)][Guid]$ExpectedUuid,[switch]$Measure)")
s=s.replace("if((Get-CimInstance Win32_ComputerSystemProduct).UUID -ne '71EC4D56-B8A9-A48C-92E8-E83EE248EC83'){throw 'Approved VMware clone only'}", "if($ExpectedUuid -notin @([Guid]'71ec4d56-b8a9-a48c-92e8-e83ee248ec83',[Guid]'2e903a40-dd97-4884-9c93-b7aeabf338fe',[Guid]'1260f534-5b49-4d00-ae8a-aa12be5987ec')){throw 'Unapproved identity'}\nif([Guid](Get-CimInstance Win32_ComputerSystemProduct).UUID -ne $ExpectedUuid){throw 'Wrong guest'}")
s=s.replace("& 'C:\\BackgroundLab\\payload\\tools\\Guest-Resolution.ps1'", "& 'C:\\BackgroundLab\\performance\\Guest-Resolution.ps1'\nif([Windows.Forms.Screen]::PrimaryScreen.Bounds.Width -ne 1920 -or [Windows.Forms.Screen]::PrimaryScreen.Bounds.Height -ne 1080){throw 'Resolution mismatch'}")
# Source function declaration has typed parameters; inject early return there.
lines=s.splitlines()
for i,line in enumerate(lines):
    if line.startswith('function Dump-App('):
        lines.insert(i+1,' if($Measure){return}')
        break
else: raise RuntimeError('Dump-App declaration missing')
s='\n'.join(lines)+'\n'
s=s.replace('Add-Type -AssemblyName UIAutomationClient', '''Add-Type 'using System.Runtime.InteropServices; public static class BcuDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[BcuDpi]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName UIAutomationClient''')
s=s.replace('Bounds.Width -ne 1920','Bounds.Width -ne 1024').replace('Bounds.Height -ne 1080','Bounds.Height -ne 768')
s=s.replace('$receiver.SetBounds(100,600,720,160)','$receiver.SetBounds(100,500,720,160)')
s=s.replace('$p=[Diagnostics.Process]::Start($si)', '$appClock=[Diagnostics.Stopwatch]::StartNew();$p=[Diagnostics.Process]::Start($si)')
s=s.replace('[DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();','[DllImport("user32.dll")]public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);\n [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();')
s=s.replace('Start-Sleep -Seconds 3\n   Dump-App', '''foreach($ownWindow in $windows){$h=[IntPtr]$ownWindow.Current.NativeWindowHandle;if($h -ne [IntPtr]::Zero){[AppInput]::SetWindowPos($h,[IntPtr]::Zero,12,20,0,0,0x15)|Out-Null}}
   Start-Sleep -Seconds 3
   Dump-App''')
s=s.replace("Start-Sleep -Seconds 3\n   Dump-App", "$startupMs=$appClock.Elapsed.TotalMilliseconds\n   Start-Sleep -Seconds 3\n   Dump-App")
s=s.replace("windows=$windows.Count;status=", "windows=$windows.Count;startupWindowMs=$startupMs;workflowMs=$appClock.Elapsed.TotalMilliseconds;cpuSeconds=$p.TotalProcessorTime.TotalSeconds;peakWorkingSetBytes=$p.PeakWorkingSet64;privateBytes=$p.PrivateMemorySize64;status=")
s=s.replace('Compress-Archive -Path "$out\\*" -DestinationPath "$out.zip" -Force', 'if(-not $Measure){Compress-Archive -Path "$out\\*" -DestinationPath "$out.zip" -Force}')
(root/'Guest-AppPerf.ps1').write_text(s,encoding='utf-8-sig')
resolution=(root.parent/'Guest-Resolution.ps1').read_text(encoding='utf-8-sig')
resolution=resolution.replace("if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'VMware guest only'}", "if([Guid](Get-CimInstance Win32_ComputerSystemProduct).UUID -notin @([Guid]'71ec4d56-b8a9-a48c-92e8-e83ee248ec83',[Guid]'2e903a40-dd97-4884-9c93-b7aeabf338fe',[Guid]'1260f534-5b49-4d00-ae8a-aa12be5987ec')){throw 'Unapproved guest'}")
resolution=resolution.replace('mode.Width=1920;mode.Height=1080','mode.Width=1024;mode.Height=768')
(root/'Guest-Resolution.ps1').write_text(resolution,encoding='utf-8-sig')
(root/'fixture-origin.json').write_text(json.dumps({'source':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'timing':'startup to UIA window observation (300ms polling); full workflow includes fixed waits; CPU and memory are target process only, not descendants'},indent=2))
