param([Parameter(Mandatory)][string]$RunId,[string]$Scenes='tabs,preset,remote,mirror')
# 게스트 TestAgent 대화형 세션에서만 실행한다. 입력은 모두 게스트 안의 SendInput이다.
$ErrorActionPreference='Stop'
if($RunId -notmatch '^[a-f0-9]{32}$'){throw 'Invalid run id'}
if((Get-CimInstance Win32_ComputerSystemProduct).UUID -ne '71EC4D56-B8A9-A48C-92E8-E83EE248EC83'){throw 'Approved VMware clone only'}
if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Interactive guest required'}
$out="C:\BackgroundLab\rec\$RunId"; New-Item -ItemType Directory $out -Force|Out-Null
function Log([string]$m){ (Get-Date -Format 'HH:mm:ss.fff')+' '+$m | Add-Content "$out\record.log" -Encoding utf8 }
trap {
 Log ("ERROR "+$_.Exception.Message+' '+$_.InvocationInfo.PositionMessage)
 @{runId=$RunId;status='failed';error=$_.Exception.Message}|ConvertTo-Json|Set-Content "$out\summary.json" -Encoding utf8
 try{ if($script:rec){$script:rec.Stop()} }catch{}
 try{ Restore-Shell }catch{}
 try{ $bb=[Windows.Forms.Screen]::PrimaryScreen.Bounds;$bm=New-Object Drawing.Bitmap $bb.Width,$bb.Height;$gg=[Drawing.Graphics]::FromImage($bm);$gg.CopyFromScreen(0,0,0,0,$bm.Size);$bm.Save("$out\fail.png");$gg.Dispose();$bm.Dispose() }catch{}
 Compress-Archive -Path "$out\*" -DestinationPath "$out-part.zip" -Force; Move-Item "$out-part.zip" "$out.zip" -Force
 break
}
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase,System.Windows.Forms,System.Drawing
& 'C:\BackgroundLab\payload\tools\Guest-Resolution.ps1'
Add-Type -ReferencedAssemblies System.Drawing,System.Windows.Forms @'
using System; using System.IO; using System.Threading; using System.Diagnostics; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices; using System.Windows.Forms;
public static class RecInput {
 [StructLayout(LayoutKind.Sequential)]public struct MouseData{public int X,Y;public uint Data,Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Sequential)]public struct KeyData{public ushort Vk,Scan;public uint Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Explicit,Size=40)]public struct Input{[FieldOffset(0)]public uint Type;[FieldOffset(8)]public MouseData Mouse;[FieldOffset(8)]public KeyData Key;}
 [DllImport("user32.dll",SetLastError=true)]static extern uint SendInput(uint n,Input[] a,int size);
 [DllImport("user32.dll")]static extern int GetSystemMetrics(int n);
 [DllImport("user32.dll")]public static extern bool GetCursorPos(out POINT p);
 [StructLayout(LayoutKind.Sequential)]public struct POINT{public int X,Y;}
 static void Send(Input a){if(SendInput(1,new Input[]{a},40)!=1)throw new Exception("Input rejected");}
 public static void Move(double x,double y){int w=GetSystemMetrics(78),h=GetSystemMetrics(79);var a=new Input();a.Mouse.X=(int)Math.Round((x-GetSystemMetrics(76))*65535.0/(w-1));a.Mouse.Y=(int)Math.Round((y-GetSystemMetrics(77))*65535.0/(h-1));a.Mouse.Flags=0xE001;Send(a);}
 public static void Button(bool down){var a=new Input();a.Mouse.Flags=down?2u:4u;Send(a);}
 public static void Key(ushort vk,bool down){var a=new Input();a.Type=1;a.Key.Vk=vk;a.Key.Flags=down?0u:2u;Send(a);}
}
public sealed class ScreenRecorder {
 [StructLayout(LayoutKind.Sequential)] struct CURSORINFO{public int cbSize;public int flags;public IntPtr hCursor;public RecInput.POINT pt;}
 [DllImport("user32.dll")] static extern bool GetCursorInfo(ref CURSORINFO ci);
 [DllImport("user32.dll")] static extern bool DrawIconEx(IntPtr hdc,int x,int y,IntPtr icon,int w,int h,int step,IntPtr brush,int flags);
 Thread _t; volatile bool _run; public int Frames; public int Errors; public string LastError=""; public long ElapsedMs;
 public void Start(string dir,int intervalMs){
  _run=true; Frames=0;
  _t=new Thread(()=>{
   var b=Screen.PrimaryScreen.Bounds; var sw=Stopwatch.StartNew();
   using(var bmp=new Bitmap(b.Width,b.Height)) using(var g=Graphics.FromImage(bmp)){
    while(_run){
     long t0=sw.ElapsedMilliseconds;
     // 백그라운드 스레드의 처리 안 된 예외는 프로세스를 죽인다 → 프레임마다 잡아 기록하고 계속
     try{
      try{ g.CopyFromScreen(b.X,b.Y,0,0,bmp.Size,CopyPixelOperation.SourceCopy|CopyPixelOperation.CaptureBlt); }
      catch(Exception){ g.CopyFromScreen(b.X,b.Y,0,0,bmp.Size,CopyPixelOperation.SourceCopy); }
      try{
       var ci=new CURSORINFO(); ci.cbSize=Marshal.SizeOf(typeof(CURSORINFO));
       if(GetCursorInfo(ref ci)&&ci.flags==1){IntPtr hdc=g.GetHdc();try{DrawIconEx(hdc,ci.pt.X-b.X,ci.pt.Y-b.Y,ci.hCursor,0,0,0,IntPtr.Zero,3);}finally{g.ReleaseHdc(hdc);}}
      }catch(Exception){}
      bmp.Save(Path.Combine(dir,string.Format("{0:D5}_{1:D7}.png",Frames,t0)),ImageFormat.Png); Frames++;
     }catch(Exception ex){ Errors++; LastError=ex.GetType().Name+": "+ex.Message; try{File.AppendAllText(Path.Combine(dir,"recorder-errors.log"),t0+" "+LastError+"\r\n");}catch{} if(Errors>200)break; }
     long wait=intervalMs-(sw.ElapsedMilliseconds-t0); if(wait>0)Thread.Sleep((int)wait);
    }
    ElapsedMs=sw.ElapsedMilliseconds;
   }
  }); _t.IsBackground=true; _t.Start();
 }
 public void Stop(){_run=false; if(_t!=null)_t.Join();}
}
// 녹화 동안 게스트 바탕화면을 단색으로, 아이콘·작업 표시줄을 숨긴다(게스트 시험 계정 안에서만)
public static class RecShell {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr p,IntPtr after,string cls,string name);
 [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h,int cmd);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool SystemParametersInfo(uint a,uint p,string v,uint f);
 [DllImport("user32.dll")] static extern bool SetSysColors(int n,int[] el,int[] colors);
 [StructLayout(LayoutKind.Sequential)] struct RECT{public int l,t,r,b;}
 [StructLayout(LayoutKind.Sequential)] struct APPBARDATA{public int cbSize;public IntPtr hWnd;public uint msg;public uint edge;public RECT rc;public IntPtr lParam;}
 [DllImport("shell32.dll")] static extern UIntPtr SHAppBarMessage(uint m,ref APPBARDATA d);
 static APPBARDATA Bar(){var d=new APPBARDATA();d.cbSize=Marshal.SizeOf(typeof(APPBARDATA));d.hWnd=FindWindowEx(IntPtr.Zero,IntPtr.Zero,"Shell_TrayWnd",null);return d;}
 public static int GetBarState(){var d=Bar();return (int)SHAppBarMessage(4,ref d).ToUInt32();}
 public static void SetBarState(int s){var d=Bar();d.lParam=(IntPtr)s;SHAppBarMessage(10,ref d);}
 public static void Taskbars(bool show){
  foreach(var cls in new[]{"Shell_TrayWnd","Shell_SecondaryTrayWnd"}){IntPtr h=IntPtr.Zero;while((h=FindWindowEx(IntPtr.Zero,h,cls,null))!=IntPtr.Zero)ShowWindow(h,show?5:0);}
 }
 public static void DesktopIcons(bool show){
  foreach(var top in new[]{"Progman","WorkerW"}){IntPtr w=IntPtr.Zero;
   while((w=FindWindowEx(IntPtr.Zero,w,top,null))!=IntPtr.Zero){IntPtr dv=FindWindowEx(w,IntPtr.Zero,"SHELLDLL_DefView",null);if(dv==IntPtr.Zero)continue;IntPtr lv=FindWindowEx(dv,IntPtr.Zero,"SysListView32",null);if(lv!=IntPtr.Zero)ShowWindow(lv,show?5:0);}}
 }
 public static void SolidDesktop(int r,int g,int b){SetSysColors(1,new[]{1},new[]{r|(g<<8)|(b<<16)});SystemParametersInfo(20,0,"",3);}
}
'@
function PauseUi([int]$Ms=250){$end=[DateTime]::UtcNow.AddMilliseconds($Ms);do{[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 10}while([DateTime]::UtcNow -lt $end)}
function Get-AppWindows([int]$ProcessId){
 $c=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$ProcessId
 return [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$c)
}
function Find-Control([int]$ProcessId,[string]$Id='',[string]$Name='',[string]$Type='',[switch]$Optional){
 # UIA 자체 조건 검색(PowerShell에서 전체 트리를 훑으면 한 번에 2초씩 걸린다)
 $conds=@()
 if($Id){$conds+=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::AutomationIdProperty),$Id}
 if($Name){$conds+=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty),$Name}
 if($Type){$conds+=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty),([Windows.Automation.ControlType]::$Type)}
 $cond=if($conds.Count -eq 0){[Windows.Automation.Condition]::TrueCondition}elseif($conds.Count -eq 1){$conds[0]}else{New-Object Windows.Automation.AndCondition (,[Windows.Automation.Condition[]]$conds)}
 for($try=0;$try -lt 16;$try++){
  foreach($w in (Get-AppWindows $ProcessId)){
   foreach($el in $w.FindAll([Windows.Automation.TreeScope]::Subtree,$cond)){
    $c=$el.Current; if($c.IsOffscreen -or $c.BoundingRectangle.Width -le 0){continue}; return $el
   }
  }
  Start-Sleep -Milliseconds 150
 }
 if($Optional){return $null}
 throw "Control unavailable: $Id / $Name / $Type"
}
function Find-ComboBySelection([int]$ProcessId,[string[]]$Values){
 $cond=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty),([Windows.Automation.ControlType]::ComboBox)
 foreach($w in (Get-AppWindows $ProcessId)){
  foreach($el in $w.FindAll([Windows.Automation.TreeScope]::Descendants,$cond)){
   if($el.Current.IsOffscreen){continue}
   try{ $sel=$el.GetCurrentPattern([Windows.Automation.SelectionPattern]::Pattern).Current.GetSelection(); if($sel.Count -gt 0 -and $Values -contains $sel[0].Current.Name){return $el} }catch{}
  }
 }
 return $null
}
function Select-ComboItem([int]$ProcessId,$Combo,[string]$Item){
 if(-not $Combo){Log "combo missing for $Item";return}
 Click-Control $Combo; PauseUi 300
 $li=Find-Control $ProcessId '' $Item 'ListItem' -Optional
 if($li){Click-Control $li}else{Press 27; Log "item missing $Item"}
}function Glide([double]$X,[double]$Y,[int]$Ms=300){
 # 시계 기준으로 움직여 Start-Sleep 오차(15.6ms 격자)가 쌓여 느려지지 않게 한다
 $p=New-Object RecInput+POINT;[RecInput]::GetCursorPos([ref]$p)|Out-Null
 $sw=[Diagnostics.Stopwatch]::StartNew()
 do{ $t=[Math]::Min(1.0,$sw.ElapsedMilliseconds/$Ms); $e=$t*$t*(3-2*$t); [RecInput]::Move($p.X+($X-$p.X)*$e,$p.Y+($Y-$p.Y)*$e); if($t -ge 1){break}; Start-Sleep -Milliseconds 10 }while($true)
}
function Click-At([double]$X,[double]$Y){ Glide $X $Y; PauseUi 70; try{[RecInput]::Button($true);PauseUi 50}finally{[RecInput]::Button($false)}; PauseUi 120 }
function Click-Control($El){ Log ("click "+$El.Current.Name); $r=$El.Current.BoundingRectangle; Click-At ($r.X+$r.Width/2) ($r.Y+$r.Height/2) }
function Press([uint16]$Vk){ [RecInput]::Key($Vk,$true); PauseUi 40; [RecInput]::Key($Vk,$false); PauseUi 150 }
function Rect($r){ @{x=[int]$r.X;y=[int]$r.Y;width=[int]$r.Width;height=[int]$r.Height} }
$script:rec=New-Object ScreenRecorder
# 바탕화면 단색(make_gifs.py 칠하기 색과 같은 24,26,30) · 아이콘·작업 표시줄 숨김. 작업 표시줄 자동 숨김 상태는 끝에 되돌린다
$script:barState=[RecShell]::GetBarState()
function Restore-Shell{ try{ [RecShell]::Taskbars($true); [RecShell]::DesktopIcons($true); [RecShell]::SetBarState($script:barState) }catch{} }
Set-ItemProperty 'HKCU:\Control Panel\Colors' Background '24 26 30'
Set-ItemProperty 'HKCU:\Control Panel\Desktop' WallPaper ''
[RecShell]::SolidDesktop(24,26,30)
[RecShell]::SetBarState(1)   # 자동 숨김: 작업 영역이 화면 아래 끝까지 넓어진다
[RecShell]::Taskbars($false); [RecShell]::DesktopIcons($false)
Log "shell: solid desktop, taskbar hidden (prev state $script:barState)"
function Begin-Scene([string]$Name){ $script:sceneDir="$out\$Name"; New-Item -ItemType Directory $script:sceneDir -Force|Out-Null; $script:rec.Start($script:sceneDir,80); PauseUi 400; Log "scene $Name start" }
function End-Scene($CropRect){ PauseUi 500; $script:rec.Stop(); $CropRect|ConvertTo-Json -Depth 5|Set-Content "$script:sceneDir\crop.json" -Encoding utf8; Log "scene end frames=$($script:rec.Frames) errors=$($script:rec.Errors) $($script:rec.LastError) ms=$($script:rec.ElapsedMs)" }

# 1. 가상 폰 연결 확인 (게스트 adb → 127.0.0.1:5555 → 호스트 중계 → 에뮬레이터)
$adbExe='C:\app\scrcpy-win64-v4.1\adb.exe'
# PS 5.1은 네이티브 stderr를 오류로 바꾸므로 adb는 cmd를 거쳐 문자열로만 받는다
function AdbRun([string]$a){ (cmd /c ('"'+$adbExe+'" '+$a+' 2>&1')) -join "`n" }
AdbRun 'start-server'|Out-Null
$found=$false
for($i=0;$i -lt 60;$i++){ $list=AdbRun 'devices'; if($list -match "emulator-5554\s+device"){$found=$true;break}; Start-Sleep 1 }
Log ("adb devices: "+((AdbRun 'devices') -replace "`n",' | '))
if(-not $found){throw 'Virtual phone not visible in guest adb'}
# 홈 화면으로 정리
AdbRun '-s emulator-5554 shell input keyevent KEYCODE_HOME'|Out-Null

# 2. GUI 실행
$si=New-Object Diagnostics.ProcessStartInfo;$si.FileName='C:\app\scrcpy-gui\ScrcpyGui.exe';$si.WorkingDirectory='C:\app\scrcpy-gui';$si.UseShellExecute=$false
$p=[Diagnostics.Process]::Start($si)
$deadline=[DateTime]::UtcNow.AddSeconds(40)
do{Start-Sleep -Milliseconds 300;$wins=Get-AppWindows $p.Id}while($wins.Count -eq 0 -and [DateTime]::UtcNow -lt $deadline)
if($wins.Count -eq 0){throw 'No GUI window'}
$main=$wins[0]
PauseUi 4000
$mr=$main.Current.BoundingRectangle; Log ("main window "+($mr.ToString()))
# 커서를 창 가운데 근처에 둔다
[RecInput]::Move($mr.X+$mr.Width*0.55,$mr.Y+$mr.Height*0.5)
$crop=Rect $mr
$sceneList=$Scenes -split ','

if($sceneList -contains 'tabs'){
 Click-Control (Find-Control $p.Id '' '화면' 'ListItem'); PauseUi 600
 Begin-Scene 'tabs'
 foreach($tab in '창','전원','입력','소리','화면'){ Click-Control (Find-Control $p.Id '' $tab 'ListItem'); PauseUi 550 }
 End-Scene $crop
}
if($sceneList -contains 'preset'){
 $hdr=Find-Control $p.Id 'HeaderSite' '고급 · 자세히 보기' 'Button' -Optional
 $details=Find-Control $p.Id 'AdvancedDetails' -Optional
 if($hdr -and $details -and $details.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Expanded){ Click-Control $hdr; PauseUi 600 }
 Begin-Scene 'preset'
 foreach($name in '고화질','가볍게','평소용'){
  $box=Find-Control $p.Id 'PresetBox'; $r=$box.Current.BoundingRectangle
  Click-At ($r.Right-14) ($r.Y+$r.Height/2); PauseUi 450
  $item=Find-Control $p.Id '' $name 'ListItem' -Optional
  if($item){ Click-Control $item } else { Press 27 }
  PauseUi 800
 }
 End-Scene $crop
}
if($sceneList -contains 'remote'){
 Click-Control (Find-Control $p.Id '' '휴대폰 조작판' 'ListItem'); PauseUi 800
 $tab=Find-Control $p.Id '' '배치·크기' 'TabItem' -Optional; if($tab){Click-Control $tab; PauseUi 600}
 Begin-Scene 'remote'
 Select-ComboItem $p.Id (Find-ComboBySelection $p.Id @('왼쪽','오른쪽')) '왼쪽'; PauseUi 1000
 Select-ComboItem $p.Id (Find-ComboBySelection $p.Id @('나눠 놓기 · 아래에 3개, 옆에 스크롤','한 줄로 놓기 · 옆에 5개')) '한 줄로 놓기 · 옆에 5개'; PauseUi 1300
 End-Scene $crop
 # 녹화 밖에서 원래 배치로 되돌린다(다음 미러링 장면이 기본 배치를 쓰도록)
 Select-ComboItem $p.Id (Find-ComboBySelection $p.Id @('나눠 놓기 · 아래에 3개, 옆에 스크롤','한 줄로 놓기 · 옆에 5개')) '나눠 놓기 · 아래에 3개, 옆에 스크롤'; PauseUi 300
 Select-ComboItem $p.Id (Find-ComboBySelection $p.Id @('왼쪽','오른쪽')) '오른쪽'; PauseUi 300
}
if($sceneList -contains 'mirror'){
 Click-Control (Find-Control $p.Id '' '화면' 'ListItem'); PauseUi 500
 Click-Control (Find-Control $p.Id 'RunButton');
 $sc=$null; for($i=0;$i -lt 60 -and -not $sc;$i++){ Start-Sleep -Milliseconds 500; $sc=Get-Process scrcpy -ErrorAction SilentlyContinue|Where-Object {$_.MainWindowHandle -ne 0}|Select-Object -First 1 }
 if(-not $sc){throw 'scrcpy window did not appear'}
 PauseUi 3500
 $sw=[Windows.Automation.AutomationElement]::FromHandle($sc.MainWindowHandle); $sr=$sw.Current.BoundingRectangle; Log ("scrcpy window "+$sr.ToString())
 # 조작판 버튼이 미러링 창에 붙을 때까지 기다린다(창 뜬 직후엔 아직 없을 수 있다)
 $buttons=@{}
 for($i=0;$i -lt 40 -and $buttons.Count -eq 0;$i++){
  foreach($w in (Get-AppWindows $p.Id)){ $n=$w.Current.Name; if($n -like '휴대폰 조작판 · *' -and -not $w.Current.IsOffscreen){ $buttons[$n.Substring('휴대폰 조작판 · '.Length)]=$w.Current.BoundingRectangle } }
  if($buttons.Count -eq 0){ PauseUi 500 }
 }
 if($buttons.Count -eq 0){
  # GUI는 영상 창을 10초만 기다린다(MainWindow.Runtime.cs). 늦게 뜨면 조작판 화면에서 창을 다시 찾아 시작한다.
  Log 'auto attach missed; selecting window from remote page'
  Click-Control (Find-Control $p.Id '' '휴대폰 조작판' 'ListItem'); PauseUi 4000
  $use=Find-Control $p.Id '' '▶ 사용하기' 'Button' -Optional; if($use){ Click-Control $use; PauseUi 1200 }
  # 조작판 화면은 3초마다 창 목록을 새로 고치므로 다른 탭으로 돌려 둔다
  Click-Control (Find-Control $p.Id '' '화면' 'ListItem'); PauseUi 800
  # 미러링 창 제목 표시줄을 눌러 앞으로(가려지면 버튼이 숨는다)
  $sr=$sw.Current.BoundingRectangle; Click-At ($sr.Left+$sr.Width/2) ($sr.Top+12); PauseUi 1500
  for($i=0;$i -lt 20 -and $buttons.Count -eq 0;$i++){
   foreach($w in (Get-AppWindows $p.Id)){ $n=$w.Current.Name; if($n -like '휴대폰 조작판 · *' -and -not $w.Current.IsOffscreen){ $buttons[$n.Substring('휴대폰 조작판 · '.Length)]=$w.Current.BoundingRectangle } }
   if($buttons.Count -eq 0){ PauseUi 500 }
  }
 }
 if($buttons.Count -eq 0){throw 'remote buttons did not attach'}
 PauseUi 800; $sr=$sw.Current.BoundingRectangle
 Log ("overlay buttons: "+(($buttons.Keys|Sort-Object) -join ','))
 $l=$sr.Left;$t=$sr.Top;$rr=$sr.Right;$b=$sr.Bottom
 foreach($v in $buttons.Values){ $l=[Math]::Min($l,$v.Left);$t=[Math]::Min($t,$v.Top);$rr=[Math]::Max($rr,$v.Right);$b=[Math]::Max($b,$v.Bottom) }
 # keep: GIF에서 남길 영역(미러링 창·조작판 버튼). 나머지는 단색으로 칠해 뒤 창 글자가 비치지 않게 한다
 $keep=@(Rect $sr); foreach($v in $buttons.Values){ $keep+=@{x=[int]$v.Left-4;y=[int]$v.Top-4;width=[int]$v.Width+8;height=[int]$v.Height+8} }
 $mcrop=@{x=[int]$l-16;y=[int]$t-16;width=[int]($rr-$l)+32;height=[int]($b-$t)+32;keep=$keep}
 [RecInput]::Move($sr.Left+$sr.Width/2,$sr.Top+$sr.Height*0.4)
 $state=(Get-AppWindows $p.Id|ForEach-Object{$_.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}|ForEach-Object{$_.Current.Name}|Where-Object{$_ -match '사용 중|일시 정지'}|Select-Object -First 1)
 Log "remote state: $state"
 Begin-Scene 'mirror'
 if($state -notmatch '사용 중' -and $buttons.ContainsKey('정지')){ $v=$buttons['정지']; Glide ($v.Left+$v.Width/2) ($v.Top+$v.Height/2) 600; PauseUi 1300 }
 foreach($name in '최근 앱','홈','뒤로'){
  if(-not $buttons.ContainsKey($name)){continue}
  $v=$buttons[$name]; Glide ($v.Left+$v.Width/2) ($v.Top+$v.Height/2) 600; PauseUi 1500
  Glide ($sr.Left+$sr.Width/2) ($sr.Top+$sr.Height*0.45) 500; PauseUi 400
 }
 End-Scene $mcrop
 Stop-Process -Id $sc.Id -ErrorAction SilentlyContinue
}
try{ $p.CloseMainWindow()|Out-Null; $p.WaitForExit(5000)|Out-Null }catch{}
Restore-Shell
@{runId=$RunId;status='complete'}|ConvertTo-Json|Set-Content "$out\summary.json" -Encoding utf8
Compress-Archive -Path "$out\*" -DestinationPath "$out-part.zip" -Force; Move-Item "$out-part.zip" "$out.zip" -Force
