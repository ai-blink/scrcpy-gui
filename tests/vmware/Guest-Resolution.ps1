$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystem).Manufacturer -ne 'VMware, Inc.'){throw 'VMware guest only'}
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class GuestDisplay {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Ansi)] public struct Mode {
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string Device;
  public ushort Spec,Driver,Size,Extra; public uint Fields;
  public int X,Y; public uint Orientation,Fixed; public short Color,Duplex,YResolution,TT,Collate;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string Form;
  public ushort LogPixels;public uint Bits,Width,Height,Flags,Frequency,ICMMethod,ICMIntent,Media,Dither,Reserved1,Reserved2,PanWidth,PanHeight;
 }
 [DllImport("user32.dll",CharSet=CharSet.Ansi)] static extern bool EnumDisplaySettings(string device,int mode,ref Mode data);
 [DllImport("user32.dll",CharSet=CharSet.Ansi)] static extern int ChangeDisplaySettings(ref Mode mode,int flags);
 public static int Set(){Mode mode=new Mode();mode.Size=(ushort)Marshal.SizeOf(typeof(Mode));if(!EnumDisplaySettings(null,-1,ref mode))return -99;mode.Width=1920;mode.Height=1080;mode.Fields=0x180000;return ChangeDisplaySettings(ref mode,0);}
}
'@
$code=[GuestDisplay]::Set()
Add-Type -AssemblyName System.Windows.Forms
@{code=$code;bounds=[Windows.Forms.Screen]::PrimaryScreen.Bounds.ToString()}|ConvertTo-Json|Set-Content C:\BackgroundLab\resolution.json
if($code -ne 0){throw "Guest display change failed: $code"}
