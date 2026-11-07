[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,[int]$DurationSeconds=120,[int]$SampleIntervalMs=20,[string]$StopFile='')
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
Add-Type @'
using System;using System.Runtime.InteropServices;using System.Collections.Generic;
public static class BcuHostObserver {
 public delegate void EventProc(IntPtr hook,uint e,IntPtr w,int o,int c,uint t,uint ms);
 [StructLayout(LayoutKind.Sequential)] public struct Point{public int X,Y;}
 [StructLayout(LayoutKind.Sequential)] public struct Rect{public int L,T,R,B;}
 [StructLayout(LayoutKind.Sequential)] public struct Message{public IntPtr H;public uint Id;public UIntPtr W;public IntPtr L;public uint Time;public Point P;public uint Private;}
 [DllImport("user32.dll")]public static extern IntPtr SetWinEventHook(uint min,uint max,IntPtr module,EventProc cb,uint p,uint t,uint flags);
 [DllImport("user32.dll")]public static extern bool UnhookWinEvent(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")]public static extern bool GetCursorPos(out Point p);
 [DllImport("user32.dll")]public static extern bool GetClipCursor(out Rect r);
 [DllImport("user32.dll")]public static extern uint GetClipboardSequenceNumber();
 [DllImport("user32.dll")]public static extern bool PeekMessage(out Message m,IntPtr h,uint min,uint max,uint flags);
 [DllImport("user32.dll")]public static extern bool TranslateMessage(ref Message m);
 [DllImport("user32.dll")]public static extern IntPtr DispatchMessage(ref Message m);
 static readonly Queue<string> events=new Queue<string>();
 static readonly EventProc callback=OnEvent;static IntPtr hook;public static int Drops;
 static void OnEvent(IntPtr h,uint e,IntPtr w,int o,int c,uint t,uint ms){uint pid;GetWindowThreadProcessId(w,out pid);lock(events){if(events.Count>=4096){Drops++;return;}events.Enqueue("{\"kind\":\"foreground_event\",\"qpc\":"+System.Diagnostics.Stopwatch.GetTimestamp()+",\"target_pid\":"+pid+",\"source_event_ms\":"+ms+",\"origin\":\"unknown_origin\"}");}}
 public static bool Start(){hook=SetWinEventHook(3,3,IntPtr.Zero,callback,0,0,0);return hook!=IntPtr.Zero;}
 public static void Pump(){Message m;while(PeekMessage(out m,IntPtr.Zero,0,0,1)){TranslateMessage(ref m);DispatchMessage(ref m);}}
 public static string[] Drain(){lock(events){var result=events.ToArray();events.Clear();return result;}}
 public static uint Pid(){uint pid;GetWindowThreadProcessId(GetForegroundWindow(),out pid);return pid;}
 public static string Sample(long qpc){Point p;Rect r;bool cursor=GetCursorPos(out p),clip=GetClipCursor(out r);return "{\"kind\":\"sample\",\"qpc\":"+qpc+",\"target_pid\":"+Pid()+",\"cursor_ok\":"+cursor.ToString().ToLowerInvariant()+",\"x\":"+p.X+",\"y\":"+p.Y+",\"clip_ok\":"+clip.ToString().ToLowerInvariant()+",\"clip\":["+r.L+","+r.T+","+r.R+","+r.B+"],\"clipboard_sequence\":"+GetClipboardSequenceNumber()+"}";}
 public static void Stop(){if(hook!=IntPtr.Zero)UnhookWinEvent(hook);}
}
'@
$writer=[IO.StreamWriter]::new((Join-Path $OutputDirectory 'host-events.ndjson'),$false,[Text.UTF8Encoding]::new($false))
$hookOk=[BcuHostObserver]::Start();$watch=[Diagnostics.Stopwatch]::StartNew();$last=[Diagnostics.Stopwatch]::GetTimestamp();$maxGap=0.0;$samples=0;$eventCount=0;$over100=0
try{
 @{status='ready';eventHook=$hookOk;pid=$PID;qpcFrequency=[Diagnostics.Stopwatch]::Frequency}|ConvertTo-Json|Set-Content (Join-Path $OutputDirectory 'observer-ready.json')
 while($watch.Elapsed.TotalSeconds -lt $DurationSeconds){
  [BcuHostObserver]::Pump()
  foreach($line in [BcuHostObserver]::Drain()){$writer.WriteLine($line);$eventCount++}
  $now=[Diagnostics.Stopwatch]::GetTimestamp();$gap=1000.0*($now-$last)/[Diagnostics.Stopwatch]::Frequency;$last=$now
  $maxGap=[Math]::Max($maxGap,$gap);if($gap -gt 100){$over100++}
  $writer.WriteLine([BcuHostObserver]::Sample($now));$samples++
  if($samples%50 -eq 0){$writer.Flush()}
  if($StopFile -and (Test-Path -LiteralPath $StopFile)){break}
  Start-Sleep -Milliseconds $SampleIntervalMs
 }
}finally{
 [BcuHostObserver]::Pump();foreach($line in [BcuHostObserver]::Drain()){$writer.WriteLine($line);$eventCount++}
 [BcuHostObserver]::Stop();$writer.Dispose()
 [ordered]@{eventHook=$hookOk;samples=$samples;foregroundEvents=$eventCount;queueDrops=[BcuHostObserver]::Drops;maxSampleGapMs=[math]::Round($maxGap,3);gapsOver100Ms=$over100;elapsedSeconds=$watch.Elapsed.TotalSeconds;observationValid=($hookOk -and $over100 -eq 0 -and [BcuHostObserver]::Drops -eq 0);hostInjection='not_used_by_this_tool';keyClickWheelLeakage='not_measured';causalAttribution='unknown_origin';isolationVerdict='insufficient_for_full_input_leakage_claim'}|ConvertTo-Json|Set-Content (Join-Path $OutputDirectory 'host-health.json')
}
