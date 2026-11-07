param([Parameter(Mandatory)][string]$RunId,[ValidateSet('Inspect','Exercise')][string]$Mode='Inspect')
$ErrorActionPreference='Stop'
if($RunId -notmatch '^[a-f0-9]{32}$'){throw 'Invalid run id'}
if((Get-CimInstance Win32_ComputerSystemProduct).UUID -ne '71EC4D56-B8A9-A48C-92E8-E83EE248EC83'){throw 'Approved VMware clone only'}
if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Interactive guest required'}
$root='C:\BackgroundLab\payload';$out="C:\BackgroundLab\app-ui\$RunId"
New-Item -ItemType Directory $out -Force|Out-Null
trap {
 @{runId=$RunId;mode=$Mode;status='failed';error=$_.Exception.Message;detail=$_.InvocationInfo.PositionMessage;guestUuid=(Get-CimInstance Win32_ComputerSystemProduct).UUID}|ConvertTo-Json -Depth 5|Set-Content "$out\summary.json" -Encoding utf8
 Compress-Archive -Path "$out\*" -DestinationPath "$out.zip" -Force
 break
}
$env:DOTNET_ROOT=if(Test-Path 'C:\Program Files\dotnet\dotnet.exe'){'C:\Program Files\dotnet'}else{Join-Path $root 'dotnet'};$env:PATH=$env:DOTNET_ROOT+';'+$env:PATH
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase,System.Windows.Forms,System.Drawing
& 'C:\BackgroundLab\payload\tools\Guest-Resolution.ps1'
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class AppInput {
 [StructLayout(LayoutKind.Sequential)]public struct MouseData{public int X,Y;public uint Data,Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Sequential)]public struct KeyData{public ushort Vk,Scan;public uint Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Explicit,Size=40)]public struct Input{[FieldOffset(0)]public uint Type;[FieldOffset(8)]public MouseData Mouse;[FieldOffset(8)]public KeyData Key;}
 [DllImport("user32.dll",SetLastError=true)]static extern uint SendInput(uint n,Input[] a,int size);
 [DllImport("user32.dll")]static extern int GetSystemMetrics(int n);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern uint GetDoubleClickTime();
 static void Send(Input a){if(SendInput(1,new Input[]{a},40)!=1)throw new Exception("Input rejected");}
 public static void Move(int x,int y){int w=GetSystemMetrics(78),h=GetSystemMetrics(79);var a=new Input();a.Mouse.X=(int)Math.Round((x-GetSystemMetrics(76))*65535.0/(w-1));a.Mouse.Y=(int)Math.Round((y-GetSystemMetrics(77))*65535.0/(h-1));a.Mouse.Flags=0xE001;Send(a);}
 public static void Button(bool down){var a=new Input();a.Mouse.Flags=down?2u:4u;Send(a);}
 public static void Key(ushort vk,bool down){var a=new Input();a.Type=1;a.Key.Vk=vk;a.Key.Flags=down?0u:2u;Send(a);}
 public static void Text(string text){foreach(char c in text){var a=new Input();a.Type=1;a.Key.Scan=c;a.Key.Flags=4;Send(a);a.Key.Flags=6;Send(a);}}
}
'@
function PauseUi([int]$Ms=250){$end=[DateTime]::UtcNow.AddMilliseconds($Ms);do{[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 10}while([DateTime]::UtcNow -lt $end)}
function Find-Control([int]$ProcessId,[string]$Id='',[string]$Name='',[string]$Type=''){
 foreach($w in (Get-AppWindows $ProcessId)){
  foreach($el in @($w)+@($w.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition))){
   $c=$el.Current
   if($Id -and $c.AutomationId -ne $Id){continue};if($Name -and $c.Name -ne $Name){continue};if($Type -and $c.ControlType.ProgrammaticName -ne "ControlType.$Type"){continue}
   if($c.IsOffscreen -or $c.BoundingRectangle.Width -le 0){continue}
   return $el
  }
 }
 throw "Control unavailable: $Id / $Name / $Type"
}
function Click-Control($El){
 $r=$El.Current.BoundingRectangle;$x=$r.X+$r.Width/2;$y=$r.Y+$r.Height/2
 $screen=[Windows.Forms.Screen]::PrimaryScreen.Bounds
 if(-not $screen.Contains([int]$x,[int]$y)){throw 'Target outside guest screen'}
 [AppInput]::Move($x,$y);PauseUi 100
 try{[AppInput]::Button($true);PauseUi 80}finally{[AppInput]::Button($false)};PauseUi 350
}
function Read-Value($El){return $El.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value}
function Enter-Text($El,[string]$Value){
 Click-Control $El
 try{[AppInput]::Key(17,$true);[AppInput]::Key(65,$true);[AppInput]::Key(65,$false)}finally{[AppInput]::Key(17,$false)}
 PauseUi 100;[AppInput]::Text($Value);PauseUi 300
}
function Record([string]$App,[string]$Action,[bool]$Pass,$Oracle){
 $r=@{runId=$RunId;app=$App;action=$Action;pass=$Pass;oracle=$Oracle}
 $script:receipts+=,$r;$r|ConvertTo-Json -Depth 7 -Compress|Add-Content "$out\actions.ndjson" -Encoding utf8
}
function Drag-Window([int]$ProcessId,$Window,[double]$StartX,[double]$StartY,[string]$App){
 $before=$Window.Current.BoundingRectangle
 Start-Sleep -Milliseconds ([AppInput]::GetDoubleClickTime()+50)
 [AppInput]::Move($StartX,$StartY);PauseUi 120
 try{[AppInput]::Button($true);PauseUi 150;for($step=1;$step -le 10;$step++){[AppInput]::Move(($StartX+8*$step),($StartY+4*$step));PauseUi 35}}finally{[AppInput]::Button($false)}
 PauseUi 400;$after=$Window.Current.BoundingRectangle
 $dx=$after.X-$before.X;$dy=$after.Y-$before.Y
 Record $App 'window_drag' ([Math]::Abs($dx-80) -le 8 -and [Math]::Abs($dy-40) -le 8) @{dx=$dx;dy=$dy;expectedDx=80;expectedDy=40}
}
function Get-AppWindows([int]$ProcessId){
 $condition=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$ProcessId
 return [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)
}
function Dump-App([int]$ProcessId,[string]$Label){
 $rows=@();$windows=Get-AppWindows $ProcessId
 foreach($window in $windows){
  $elements=@($window)+@($window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition))
  foreach($element in $elements){
   try{
    $c=$element.Current;$r=$c.BoundingRectangle
    $value=$null;$pattern=$null
    if(-not $c.IsPassword -and $element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)){$value=$pattern.Current.Value}
    $rows+=@{id=$c.AutomationId;name=$c.Name;type=$c.ControlType.ProgrammaticName;class=$c.ClassName;enabled=$c.IsEnabled;offscreen=$c.IsOffscreen;hwnd=$c.NativeWindowHandle;rect=@{x=$r.X;y=$r.Y;width=$r.Width;height=$r.Height};value=$value}
   }catch{}
  }
 }
 ConvertTo-Json -InputObject @($rows) -Depth 5|Set-Content "$out\$Label-tree.json" -Encoding utf8
 $bounds=[Windows.Forms.Screen]::PrimaryScreen.Bounds;$bmp=New-Object Drawing.Bitmap $bounds.Width,$bounds.Height;$g=[Drawing.Graphics]::FromImage($bmp)
 try{$g.CopyFromScreen($bounds.X,$bounds.Y,0,0,$bmp.Size);$bmp.Save("$out\$Label.png")}finally{$g.Dispose();$bmp.Dispose()}
}
$apps=@();$receipts=@()
try{
 foreach($case in @(@{name='scrcpy-gui';exe='ScrcpyGui.exe'},@{name='key-demo-osk';exe='FlowType.OSK.exe'},@{name='new-alt';exe='AltController.Next.App.exe'})){
  $p=$null
  try{
   $exe=Join-Path "$root\apps\$($case.name)" $case.exe
   $si=New-Object Diagnostics.ProcessStartInfo;$si.FileName=$exe;$si.WorkingDirectory=Split-Path $exe;$si.UseShellExecute=$false
   $p=[Diagnostics.Process]::Start($si)
   $deadline=[DateTime]::UtcNow.AddSeconds(30)
   do{Start-Sleep -Milliseconds 300;$windows=Get-AppWindows $p.Id}while($windows.Count -eq 0 -and -not $p.HasExited -and [DateTime]::UtcNow -lt $deadline)
   if($p.HasExited -or $windows.Count -eq 0){throw 'No app window'}
   Start-Sleep -Seconds 3
   Dump-App $p.Id $case.name
   if($Mode -eq 'Exercise'){
    if($case.name -eq 'scrcpy-gui'){
     $nav=Find-Control $p.Id '' '창' 'ListItem';Click-Control $nav
     $selected=$nav.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
     Record $case.name 'click_navigation' $selected @{selected=$selected}
     Click-Control (Find-Control $p.Id '' '화면' 'ListItem')
     $fps=Find-Control $p.Id '' '최대 프레임' 'ComboBox'
     $edit=$fps.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty),([Windows.Automation.ControlType]::Edit)))
     $old=Read-Value $edit;Enter-Text $edit '45';$received=Read-Value $edit
     Record $case.name 'text_fps' ($received -eq '45') @{expected='45';received=$received}
     $details=Find-Control $p.Id 'AdvancedDetails'
     $expand=$details.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern)
     if($expand.Current.ExpandCollapseState -eq [Windows.Automation.ExpandCollapseState]::Expanded){Click-Control (Find-Control $p.Id 'HeaderSite' '고급 · 자세히 보기' 'Button')}
     Click-Control (Find-Control $p.Id 'HeaderSite' '고급 · 자세히 보기' 'Button')
     $preview=Find-Control $p.Id 'CommandPreviewBox';$command=Read-Value $preview
     Record $case.name 'click_advanced_command' ($command -match '--max-fps[= ]45') @{commandContainsExpectedFps=($command -match '--max-fps[= ]45')}
     Enter-Text $edit $old
     $w=Find-Control $p.Id '' 'scrcpy 설정' 'Window';$title=Find-Control $p.Id 'TitleBar';$r=$title.Current.BoundingRectangle
     Drag-Window $p.Id $w ($r.X+180) ($r.Y+10) $case.name
    }elseif($case.name -eq 'key-demo-osk'){
     $receiver=New-Object Windows.Forms.Form;$receiver.Text='BCU app input receiver';$receiver.StartPosition='Manual';$receiver.SetBounds(100,600,720,160)
     $box=New-Object Windows.Forms.TextBox;$box.Multiline=$true;$box.ImeMode='Disable';$box.Dock='Fill';$receiver.Controls.Add($box)
     try{
      $receiver.Show();$receiver.Activate();$box.Focus();PauseUi 1500
      foreach($key in @('Key_A','Key_B','Key_C')){Click-Control (Find-Control $p.Id $key)}
      PauseUi 800;$actual=$box.Text
      Record $case.name 'keyboard_click_text' ($actual -ceq 'abc') @{expected='abc';received=$actual;receiverForeground=([AppInput]::GetForegroundWindow() -eq $receiver.Handle)}
      $w=Find-Control $p.Id '' 'FlowKey OSK' 'Window';$r=$w.Current.BoundingRectangle
      Drag-Window $p.Id $w ($r.X+450) ($r.Y+75) $case.name
      Record $case.name 'focus_after_drag' ([AppInput]::GetForegroundWindow() -eq $receiver.Handle) @{receiverForeground=([AppInput]::GetForegroundWindow() -eq $receiver.Handle)}
      Dump-App $p.Id ($case.name+'-after')
     }finally{$receiver.Close();$receiver.Dispose()}
    }else{
     Click-Control (Find-Control $p.Id '' '현재 프로필과 구성 관리' 'Button');PauseUi 600
     Dump-App $p.Id 'new-alt-profile'
     $edit=Find-Control $p.Id '' '프로필 이름' 'Edit';$old=Read-Value $edit
     Record $case.name 'click_profile_management' $true @{editorVisible=$true}
     $value='BCU-'+$RunId.Substring(0,8);Enter-Text $edit $value;$actual=Read-Value $edit
     Record $case.name 'profile_text_input' ($actual -ceq $value) @{expected=$value;received=$actual}
     Enter-Text $edit $old
     $w=Find-Control $p.Id '' 'AltController.Next 프로필 및 모드' 'Window'
     if(-not $w){throw 'Profile window missing'};$r=$w.Current.BoundingRectangle
     Drag-Window $p.Id $w ($r.X+150) ($r.Y+12) $case.name
    }
    Dump-App $p.Id ($case.name+'-final')
   }
   $apps+=@{name=$case.name;pid=$p.Id;path=$exe;sha256=(Get-FileHash $exe).Hash;windows=$windows.Count;status=$(if($Mode -eq 'Exercise'){'exercised'}else{'inspected'})}
  }catch{$apps+=@{name=$case.name;status='failed';error=$_.Exception.Message}}finally{
   if($p -and -not $p.HasExited){$p.CloseMainWindow()|Out-Null;if(-not $p.WaitForExit(2000)){$p.Kill();$p.WaitForExit(3000)|Out-Null}}
  }
 }
}finally{
 @{runId=$RunId;mode=$Mode;apps=$apps;receipts=$receipts;status='complete';guestUuid=(Get-CimInstance Win32_ComputerSystemProduct).UUID}|ConvertTo-Json -Depth 8|Set-Content "$out\summary.json" -Encoding utf8
 Compress-Archive -Path "$out\*" -DestinationPath "$out.zip" -Force
}
