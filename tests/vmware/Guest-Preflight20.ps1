param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$ExpectedUuid,[ValidateSet(20,200)][int]$ActionsPerRound=20,[ValidateRange(1,3)][int]$Rounds=1,[switch]$LegacyDrag)
$ErrorActionPreference='Stop'
if($RunId -notmatch '^[a-zA-Z0-9-]+$'){throw 'Invalid nonce'}
$identity=Get-CimInstance Win32_ComputerSystemProduct
if(([Guid]$identity.UUID) -ne ([Guid]$ExpectedUuid)){throw 'Guest UUID mismatch'}
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -notmatch 'VMware|QEMU|Microsoft Corporation'){throw 'Guest only'}
if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Interactive guest session required'}
$out="C:\BackgroundLab\preflight\$RunId";New-Item -ItemType Directory $out -Force|Out-Null
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class PreflightInput {
 [StructLayout(LayoutKind.Sequential)]public struct Key{public ushort Vk,Scan;public uint Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Sequential)]public struct MouseData{public int X,Y;public uint Data,Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Explicit,Size=40)]public struct Input{[FieldOffset(0)]public uint Type;[FieldOffset(8)]public Key Key;[FieldOffset(8)]public MouseData Mouse;}
 [DllImport("user32.dll",SetLastError=true)]static extern uint SendInput(uint n,Input[] inputs,int size);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint data,UIntPtr e);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern IntPtr GetCapture();
 [DllImport("user32.dll")]public static extern uint GetDoubleClickTime();
 [DllImport("user32.dll")]static extern int GetSystemMetrics(int n);
 [DllImport("user32.dll")]public static extern IntPtr GetThreadDesktop(uint t);
 [DllImport("user32.dll")]public static extern IntPtr OpenInputDesktop(uint f,bool i,uint a);
 [DllImport("user32.dll")]public static extern bool CloseDesktop(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern bool GetUserObjectInformation(IntPtr h,int n,System.Text.StringBuilder b,int size,out int needed);
 [DllImport("kernel32.dll")]static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")]public static extern IntPtr SendMessage(IntPtr w,uint m,IntPtr a,IntPtr b);
 public static string Desktop(bool input){IntPtr h=input?OpenInputDesktop(0,false,1):GetThreadDesktop(GetCurrentThreadId());if(h==IntPtr.Zero)throw new Exception("Desktop unavailable");try{var b=new System.Text.StringBuilder(256);int n;if(!GetUserObjectInformation(h,2,b,512,out n))throw new Exception("Desktop name unavailable");return b.ToString();}finally{if(input)CloseDesktop(h);}}
 public static void Text(string s){if(IntPtr.Size!=8)throw new Exception("x64 only");foreach(char c in s){var x=new Input[2];x[0].Type=x[1].Type=1;x[0].Key.Scan=x[1].Key.Scan=c;x[0].Key.Flags=4;x[1].Key.Flags=6;if(SendInput(2,x,40)!=2)throw new Exception("Partial Unicode diagnostic injection");}}
 public static void Mouse(uint flag,int data=0){mouse_event(flag,0,0,unchecked((uint)data),UIntPtr.Zero);}
 public static void MoveInput(int x,int y){
  int left=GetSystemMetrics(76),top=GetSystemMetrics(77),width=GetSystemMetrics(78),height=GetSystemMetrics(79);
  if(width<2||height<2)throw new Exception("Invalid virtual desktop");
  var a=new Input[1];a[0].Mouse.X=(int)Math.Round((x-left)*65535.0/(width-1));a[0].Mouse.Y=(int)Math.Round((y-top)*65535.0/(height-1));
  a[0].Mouse.Flags=0x8000|0x4000|0x2000|1;
  if(SendInput(1,a,40)!=1)throw new Exception("Mouse move injection rejected");
 }
}
'@
$desktop=[PreflightInput]::Desktop($false);$inputDesktop=[PreflightInput]::Desktop($true)
if($desktop -ne $inputDesktop){throw 'Fixture desktop is not the guest input desktop'}
$form=New-Object Windows.Forms.Form;$form.Text="BCU fixture $RunId";$form.Width=720;$form.Height=480;$form.TopMost=$true
$text=New-Object Windows.Forms.TextBox;$text.Multiline=$true;$text.ImeMode='Disable';$text.SetBounds(20,20,650,300);$text.ScrollBars='Vertical';$text.ShortcutsEnabled=$false;$text.ContextMenu=New-Object Windows.Forms.ContextMenu
Add-Type -ReferencedAssemblies System.Windows.Forms @'
using System;using System.Windows.Forms;
public class DragTrace:NativeWindow {
 public int Downs,DoubleClicks,Ups,HeldMoves,DownSelection;
 TextBox box;
 public DragTrace(TextBox b){box=b;AssignHandle(b.Handle);}
 public void Reset(){Downs=DoubleClicks=Ups=HeldMoves=DownSelection=0;}
 protected override void WndProc(ref Message m){
  int id=m.Msg;long flags=m.WParam.ToInt64();base.WndProc(ref m);
  if(id==0x201){Downs++;DownSelection=box.SelectionLength;}
  if(id==0x203){DoubleClicks++;DownSelection=box.SelectionLength;}
  if(id==0x202)Ups++;
  if(id==0x200 && (flags&1)!=0)HeldMoves++;
 }
}
'@
$trace=New-Object DragTrace($text)
$panel=New-Object Windows.Forms.Panel;$panel.SetBounds(20,340,200,60)
$form.Controls.AddRange(@($text,$panel));$state=@{left=0;right=0;qpc=0}
$text.Add_MouseDown({param($s,$e);if($e.Button -eq 'Left'){$state.left++};if($e.Button -eq 'Right'){$state.right++};$state.qpc=[Diagnostics.Stopwatch]::GetTimestamp()})
$text.Add_TextChanged({$state.qpc=[Diagnostics.Stopwatch]::GetTimestamp()})
function Pump { [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 30;[Windows.Forms.Application]::DoEvents() }
function MoveTo([int]$x,[int]$y){[Windows.Forms.Cursor]::Position=$text.PointToScreen((New-Object Drawing.Point $x,$y));Pump}
function AwaitInput([scriptblock]$Condition,[string]$Stage){
 $deadline=[DateTime]::UtcNow.AddSeconds(2)
 do{[Windows.Forms.Application]::DoEvents();if(& $Condition){return};Start-Sleep -Milliseconds 1}while([DateTime]::UtcNow -lt $deadline)
 throw "Input acknowledgement timeout: $Stage"
}
$records=@();$leftDown=$false;$rightDown=$false
try{
 $form.Show();$form.Activate();$text.Focus();Pump
 for($sequence=1;$sequence -le ($ActionsPerRound*$Rounds);$sequence++){
  $i=(($sequence-1)%20)+1;$round=[int][Math]::Floor(($sequence-1)/$ActionsPerRound)+1
  $ok=$false;$errorText=$null;$kind='';$oracle=@{};$start=[Diagnostics.Stopwatch]::GetTimestamp()
  try{
   if($i -le 6){
    $kind=if($i -eq 5){'double_click'}elseif($i -eq 6){'right_click'}else{'left_click'}
    $state.left=0;$state.right=0;MoveTo 30 30;$start=[Diagnostics.Stopwatch]::GetTimestamp()
    $times=if($i -eq 5){2}else{1};for($j=0;$j -lt $times;$j++){
     if($i -eq 6){$rightDown=$true;[PreflightInput]::Mouse(8);[PreflightInput]::Mouse(16);$rightDown=$false}else{$leftDown=$true;[PreflightInput]::Mouse(2);[PreflightInput]::Mouse(4);$leftDown=$false};Pump
    }
    $ok=if($i -eq 6){$state.right -eq 1}else{$state.left -eq $times};$oracle=@{leftDownReceived=$state.left;rightDownReceived=$state.right}
   }elseif($i -le 10){
    $kind='unicode_diagnostic_not_ime';$text.Clear();$text.Focus();$value="BCU-$i-$($RunId.Substring(0,8))";Pump;$start=[Diagnostics.Stopwatch]::GetTimestamp();[PreflightInput]::Text($value);Pump
    $ok=$text.Text -ceq $value;$oracle=@{expectedLength=$value.Length;receivedLength=$text.Text.Length}
   }elseif($i -le 14){
    $kind='wheel';$text.Lines=@(1..200|ForEach-Object{"fixture line $_"});$text.SelectionStart=$text.GetFirstCharIndexFromLine(100);$text.ScrollToCaret();$text.Focus();MoveTo 70 100
    $before=[PreflightInput]::SendMessage($text.Handle,206,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32();$delta=if($i%2){120}else{-120};$times=if($i -gt 12){3}else{1}
    $start=[Diagnostics.Stopwatch]::GetTimestamp();for($j=0;$j -lt $times;$j++){[PreflightInput]::Mouse(2048,$delta);Pump}
    $after=[PreflightInput]::SendMessage($text.Handle,206,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32();$ok=if($delta -gt 0){$after -lt $before}else{$after -gt $before};$oracle=@{firstLineBefore=$before;firstLineAfter=$after;wheelNotches=$times}
   }elseif($i -le 17){
    $kind='drag_selection'
    # Separate independent drags beyond the OS multi-click interval.
    # This setup delay is outside the measured drag interval.
    if(-not $LegacyDrag){Start-Sleep -Milliseconds ([PreflightInput]::GetDoubleClickTime()+50);[Windows.Forms.Application]::DoEvents()}
    $text.Text='ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';$text.Select(0,0);MoveTo 5 8;$trace.Reset();$start=[Diagnostics.Stopwatch]::GetTimestamp();$leftDown=$true;[PreflightInput]::Mouse(2)
    if($LegacyDrag){Pump;MoveTo (80+($i-15)*30) 8}else{
     AwaitInput {$trace.Downs -eq 1 -and [PreflightInput]::GetCapture() -eq $text.Handle} 'left down and capture'
     $target=$text.PointToScreen((New-Object Drawing.Point (80+($i-15)*30),8))
     [PreflightInput]::MoveInput($target.X,$target.Y)
     AwaitInput {$trace.HeldMoves -gt 0 -and $text.SelectionLength -gt 0} 'held move and selection'
    }
    [PreflightInput]::Mouse(4);$leftDown=$false
    if($LegacyDrag){Pump}else{AwaitInput {$trace.Ups -eq 1 -and [PreflightInput]::GetCapture() -eq [IntPtr]::Zero} 'left up and release'}
    $ok=$text.SelectionLength -gt 0 -and [PreflightInput]::GetCapture() -eq [IntPtr]::Zero;$oracle=@{leftDownMessages=$trace.Downs;doubleClickMessages=$trace.DoubleClicks;leftUpMessages=$trace.Ups;heldMoveMessages=$trace.HeldMoves;selectionAfterDown=$trace.DownSelection;doubleClickTimeMs=[PreflightInput]::GetDoubleClickTime();legacyDrag=[bool]$LegacyDrag;selectionLength=$text.SelectionLength;captureReleased=([PreflightInput]::GetCapture() -eq [IntPtr]::Zero)}
   }else{
    $kind='frame_marker';$color=[Drawing.Color]::FromArgb(255,($sequence*11)%256,83,151);$panel.BackColor=$color;Pump;$point=$panel.PointToScreen((New-Object Drawing.Point 50,20));$bmp=New-Object Drawing.Bitmap 1,1;$g=[Drawing.Graphics]::FromImage($bmp);$start=[Diagnostics.Stopwatch]::GetTimestamp();$g.CopyFromScreen($point.X,$point.Y,0,0,$bmp.Size);$actual=$bmp.GetPixel(0,0).ToArgb();$ok=$actual -eq $color.ToArgb();$oracle=@{expectedArgb=$color.ToArgb();actualArgb=$actual;frameSequence=$i};$bmp.Save("$out\frame-$sequence.png");$g.Dispose();$bmp.Dispose()
   }
  }catch{$errorText=$_.Exception.Message;if($leftDown){[PreflightInput]::Mouse(4);$leftDown=$false};if($rightDown){[PreflightInput]::Mouse(16);$rightDown=$false}}
  $end=[Diagnostics.Stopwatch]::GetTimestamp()
  $record=[ordered]@{runId=$RunId;actionId=('action-{0:d4}' -f $sequence);round=$round;sequence=$sequence;kind=$kind;status=if($ok){'pass'}else{'fail'};guestLocalCompletionMs=1000.0*($end-$start)/[Diagnostics.Stopwatch]::Frequency;oracle=$oracle;error=$errorText;foregroundMatchesFixture=([PreflightInput]::GetForegroundWindow() -eq $form.Handle)}
  $records+=$record;$record|ConvertTo-Json -Depth 5 -Compress|Add-Content "$out\actions.ndjson" -Encoding utf8
 }
}finally{
 if($leftDown){[PreflightInput]::Mouse(4)};if($rightDown){[PreflightInput]::Mouse(16)}
 $form.Close();$form.Dispose()
 [ordered]@{runId=$RunId;expectedUuid=$ExpectedUuid;actualUuid=$identity.UUID;desktop=$desktop;inputDesktop=$inputDesktop;planned=($ActionsPerRound*$Rounds);actionsPerRound=$ActionsPerRound;rounds=$Rounds;timingDefinition='guest workflow completion including fixed waits except acknowledged drag; not raw input latency';executed=$records.Count;pass=@($records|Where-Object status -eq pass).Count;fail=@($records|Where-Object status -eq fail).Count;ime='not_measured';keyHold='not_measured';hostInputLeakage='not_measured';fixtureRevision='drag-input-ack-v3';legacyDrag=[bool]$LegacyDrag;suite='synthetic_preflight_not_product_acceptance';status='complete'}|ConvertTo-Json|Set-Content "$out\summary.json" -Encoding utf8
}
