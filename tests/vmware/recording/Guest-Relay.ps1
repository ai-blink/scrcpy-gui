param([int]$HostPort=25801,[int]$AdbPort=5555)
# 게스트 쪽 짝짓기 중계. 호스트 중계가 HostPort로 들어오면, 게스트 adb가
# 127.0.0.1:AdbPort(에뮬레이터 자동 탐색 포트 → emulator-5554)로 붙을 때 둘을 잇는다.
$ErrorActionPreference='Stop'
if((Get-CimInstance Win32_ComputerSystemProduct).UUID -ne '71EC4D56-B8A9-A48C-92E8-E83EE248EC83'){throw 'Approved VMware clone only'}
Add-Type @'
using System; using System.IO; using System.Net; using System.Net.Sockets; using System.Threading.Tasks;
public static class PairRelay {
 public static void Run(int hostPort,int adbPort,string log){
  var hostL=new TcpListener(IPAddress.Any,hostPort); hostL.Start();
  var adbL=new TcpListener(IPAddress.Loopback,adbPort); adbL.Start();
  while(true){
   var h=hostL.AcceptTcpClient();
   var a=adbL.AcceptTcpClient();
   h.NoDelay=true; a.NoDelay=true;
   File.AppendAllText(log,DateTime.Now.ToString("HH:mm:ss")+" paired\r\n");
   var hs=h.GetStream(); var s=a.GetStream();
   Task.WaitAny(hs.CopyToAsync(s),s.CopyToAsync(hs));
   try{h.Close();}catch{} try{a.Close();}catch{}
   File.AppendAllText(log,DateTime.Now.ToString("HH:mm:ss")+" closed\r\n");
  }
 }
}
'@
[PairRelay]::Run($HostPort,$AdbPort,'C:\BackgroundLab\rec\relay.log')
