param([string]$Root='C:\BackgroundLab\payload',[string]$RunId='manual')
$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'VMware guest only'}
if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Interactive guest session required'}
$env:DOTNET_ROOT=Join-Path $Root 'dotnet';$env:PATH=$env:DOTNET_ROOT+';'+$env:PATH
$out=Join-Path "$Root\results" $RunId;New-Item -ItemType Directory $out -Force|Out-Null
function Trace([string]$value){$value|Set-Content "$out\probe-stage.txt"}
Trace 'initializing'
Start-Transcript -Path "$out\probe.log" -Force|Out-Null
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class GuestInput {
 private delegate bool WindowCallback(IntPtr w,IntPtr p);
 [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback c,IntPtr p);
 [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr w,out uint p);
 [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr w);
 public static int VisibleWindows(int pid){int count=0;EnumWindows(delegate(IntPtr w,IntPtr p){uint id;GetWindowThreadProcessId(w,out id);if(id==pid && IsWindowVisible(w))count++;return true;},IntPtr.Zero);return count;}
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr w,int c);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
}
'@
$results=@()
foreach($case in @(@{name='scrcpy-gui';exe='ScrcpyGui.exe'},@{name='key-demo-osk';exe='FlowType.OSK.exe'},@{name='new-alt';exe='AltController.Next.App.exe'})){
 $p=$null
 try{
  Trace "starting $($case.name)"
  $exe=Join-Path "$Root\apps\$($case.name)" $case.exe
  $si=New-Object Diagnostics.ProcessStartInfo;$si.FileName=$exe;$si.WorkingDirectory=Split-Path $exe;$si.UseShellExecute=$false;$si.CreateNoWindow=$true
  $p=[Diagnostics.Process]::Start($si)
  Trace "waiting $($case.name) PID $($p.Id)"
  $clock=[Diagnostics.Stopwatch]::StartNew()
  do{Start-Sleep -Milliseconds 300;$p.Refresh()}while(-not $p.HasExited -and [GuestInput]::VisibleWindows($p.Id) -eq 0 -and $clock.Elapsed.TotalSeconds -lt 30)
  $results+=@{name=$case.name;pid=$p.Id;alive=(-not $p.HasExited);visibleWindows=[GuestInput]::VisibleWindows($p.Id);mainWindow=$p.MainWindowHandle.ToInt64();responding=if($p.HasExited){$false}else{$p.Responding};path=$exe;sha256=(Get-FileHash $exe -Algorithm SHA256).Hash}
  Trace "capturing $($case.name)"
  $bmp=New-Object Drawing.Bitmap([Windows.Forms.Screen]::PrimaryScreen.Bounds.Width),([Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
  $g=[Drawing.Graphics]::FromImage($bmp);$g.CopyFromScreen(0,0,0,0,$bmp.Size);$bmp.Save("$out\$($case.name).png");$g.Dispose();$bmp.Dispose()
 }catch{$results+=@{name=$case.name;error=$_.Exception.Message}}finally{if($p -and -not $p.HasExited){$p.Kill();$null=$p.WaitForExit(3000)}}
 $results|ConvertTo-Json -Depth 5|Set-Content "$out\apps.json" -Encoding utf8
}
$results|ConvertTo-Json -Depth 5|Set-Content "$out\apps.json" -Encoding utf8
Trace 'guest-input'
# Real input is emitted only after checking this is a VMware interactive guest.
$form=New-Object Windows.Forms.Form;$form.Text='Isolated guest input target';$form.Width=640;$form.Height=420;$form.TopMost=$true
$text=New-Object Windows.Forms.TextBox;$text.Multiline=$true;$text.ImeMode=[Windows.Forms.ImeMode]::Disable;$text.Dock='Fill';$form.Controls.Add($text);$form.Show();$form.Activate();$text.Focus();[Windows.Forms.Application]::DoEvents()
[GuestInput]::ShowWindow($form.Handle,5)|Out-Null
[Windows.Forms.Application]::DoEvents()
$before=[Windows.Forms.Cursor]::Position
for($i=0;$i -lt 20;$i++){
 [Windows.Forms.Cursor]::Position=New-Object Drawing.Point (70+$i*10),(100+$i*5)
 [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 60
}
$point=$text.PointToScreen((New-Object Drawing.Point 20,20));[Windows.Forms.Cursor]::Position=$point
[GuestInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[GuestInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 200
[Windows.Forms.SendKeys]::SendWait('ISOLATED_BACKGROUND_INPUT_20261103');[Windows.Forms.Application]::DoEvents()
$ok=$text.Text -eq 'ISOLATED_BACKGROUND_INPUT_20261103'
$dragStart=$text.PointToScreen((New-Object Drawing.Point 5,8));$dragEnd=$text.PointToScreen((New-Object Drawing.Point 150,8))
[Windows.Forms.Cursor]::Position=$dragStart;[Windows.Forms.Application]::DoEvents()
[GuestInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[Windows.Forms.Application]::DoEvents()
[Windows.Forms.Cursor]::Position=$dragEnd;[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 80
[GuestInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero);[Windows.Forms.Application]::DoEvents()
@{textAccepted=$ok;dragSelectionLength=$text.SelectionLength;guestCursorBefore=@{x=$before.X;y=$before.Y};guestCursorAfter=@{x=[Windows.Forms.Cursor]::Position.X;y=[Windows.Forms.Cursor]::Position.Y};guestForegroundMatchesTarget=([GuestInput]::GetForegroundWindow() -eq $form.Handle);session=[Diagnostics.Process]::GetCurrentProcess().SessionId}|ConvertTo-Json -Depth 4|Set-Content "$out\guest-input.json" -Encoding utf8
$form.Close();$form.Dispose()
if(-not $ok){throw 'Guest text input was not accepted'}
Trace 'complete'
Stop-Transcript|Out-Null
