using ScrcpyGui;
using System.Diagnostics;
using System.Reflection;
using System.Security.Cryptography;

internal static class Program
{
 static int count;
 static void Check(bool value,string name){if(!value)throw new Exception(name);count++;Console.WriteLine("PASS "+name);}
 const string Serial="test-device._adb-tls-connect._tcp";
 static string Dump(string body)=>"Packages:\n  Package ["+BlinkLinkProvisioner.Package+"] (123):\n"+body;
 static readonly string Granted=Dump("    install permissions:\n      android.permission.WRITE_SECURE_SETTINGS: granted=true\n    User 0: installed=true\n");
 static async Task<int> Main(string[] args)
 {
  try
  {
   if(args.Length==3&&args[0]=="--emulator")return await Emulator(args[1],args[2]);
   var apk=Path.GetFullPath("app/android/BlinkLink-0.3.2-debug.apk");
   Check(BlinkLinkProvisioner.HasSecureSettingsPermission(Granted,"0"),"global development grant recognized");
   Check(!BlinkLinkProvisioner.HasSecureSettingsPermission(Granted.Replace("granted=true","granted=false"),"0"),"denied permission rejected");
   var perUser=Dump("    User 0: installed=true\n      android.permission.WRITE_SECURE_SETTINGS: granted=true\n    User 10: installed=true\n      android.permission.WRITE_SECURE_SETTINGS: granted=false\n");
   Check(!BlinkLinkProvisioner.HasSecureSettingsPermission(perUser,"10"),"other user's grant rejected");
   Check(BlinkLinkProvisioner.HasSecureSettingsPermission(perUser,"0"),"target user's grant recognized");
   Check(!BlinkLinkProvisioner.HasSecureSettingsPermission("android.permission.WRITE_SECURE_SETTINGS: granted=true","0"),"unscoped output rejected");
   var calls=new List<string[]>();
   async Task<BlinkAdbResult> Fake(IReadOnlyList<string> arguments,CancellationToken token,TimeSpan timeout)
   {
    await Task.Yield();var a=arguments.ToArray();calls.Add(a);token.ThrowIfCancellationRequested();
    var command=string.Join(' ',a.Skip(2));
    return command switch {"get-state"=>new(0,"device"),"shell am get-current-user"=>new(0,"0"),_ when a.Contains("install")=>new(0,"Performing Streamed Install\nSuccess\n"),_ when a.Contains("dumpsys")=>new(0,Granted),_=>new(0,"")};
   }
   var sut=new BlinkLinkProvisioner(Fake);var result=await sut.PrepareAsync(Serial,apk,null,CancellationToken.None);
   Check(result.Serial==Serial&&result.UserId=="0","successful explicit target preparation");
   Check(calls.All(a=>a[0]=="-s"&&a[1]==Serial),"every command pins selected device");
   Check(calls.Any(a=>a.SequenceEqual(new[]{"-s",Serial,"install","--user","0","-r",apk})),"update install keeps data and uses current user");
   Check(!calls.Any(a=>a.Contains("uninstall")||a.Contains("-d")||a.Contains("kill-server")),"no uninstall downgrade or server kill");
   Check(calls.Any(a=>string.Join(' ',a).Contains("pm grant --user 0 "+BlinkLinkProvisioner.Package)),"grant targets only Blink Link current user");
   Check(calls.FindIndex(a=>a.Contains("dumpsys"))<calls.FindIndex(a=>a.Contains("start")),"permission verified before app opening");
   foreach(var serial in new[]{"","two devices","-d","bad\nserial"}){int before=calls.Count;try{await sut.PrepareAsync(serial,apk,null,CancellationToken.None);throw new Exception("bad target accepted");}catch(InvalidOperationException){}Check(calls.Count==before,"invalid target causes no commands");}
   await Failure("get-state",new(0,"offline"),"install",apk);
   await Failure("grant",new(1,"policy denied"),"start",apk);
   await Failure("install",new(1,"INSTALL_FAILED_UPDATE_INCOMPATIBLE"),"grant",apk);
   await Failure("dumpsys",new(0,Granted.Replace("granted=true","granted=false")),"start",apk);
   var changes=0;calls.Clear();var switched=new BlinkLinkProvisioner((a,t,d)=>{calls.Add(a.ToArray());if(a.Contains("get-current-user"))return Task.FromResult(new BlinkAdbResult(0,++changes==1?"0":"10"));return Fake(a,t,d);});
   try{await switched.PrepareAsync(Serial,apk,null,CancellationToken.None);throw new Exception("user switch accepted");}catch(InvalidOperationException){}Check(!calls.Any(a=>a.Contains("grant")),"user switch aborts before grant");
   using var cancel=new CancellationTokenSource();calls.Clear();var cancelled=new BlinkLinkProvisioner(async(a,t,d)=>{var r=await Fake(a,t,d);if(a.Contains("install"))cancel.Cancel();return r;});
   try{await cancelled.PrepareAsync(Serial,apk,null,cancel.Token);throw new Exception("cancellation ignored");}catch(OperationCanceledException){}Check(!calls.Any(a=>a.Contains("grant")),"cancelled install does not proceed to grant");
   var bad=Path.GetTempFileName();try{int before=calls.Count;try{await sut.PrepareAsync(Serial,bad,null,CancellationToken.None);throw new Exception("wrong APK accepted");}catch(InvalidOperationException){}Check(calls.Count==before,"wrong APK hash rejected before device commands");}finally{File.Delete(bad);}
   var assembly=Assembly.LoadFrom(Path.GetFullPath("src/ScrcpyGui/bin/Release/net8.0-windows/win-x64/ScrcpyGui.dll"));using var embedded=assembly.GetManifestResourceStream("BlinkLink.apk");Check(embedded!=null&&Convert.ToHexString(SHA256.HashData(embedded)).Equals(BlinkLinkProvisioner.ApkSha256,StringComparison.OrdinalIgnoreCase),"WPF application embeds verified APK");
   Console.WriteLine("PASS "+count+" setup assertions");return 0;
  }
  catch(Exception ex){Console.Error.WriteLine(ex);return 1;}
 }
 static async Task Failure(string failing,BlinkAdbResult error,string forbidden,string apk)
 {
  var calls=new List<string[]>();var sut=new BlinkLinkProvisioner((a,t,d)=>{calls.Add(a.ToArray());return Task.FromResult(a.Contains(failing)?error:a.Contains("get-state")?new BlinkAdbResult(0,"device"):a.Contains("get-current-user")?new(0,"0"):a.Contains("install")?new(0,"Success"):new(0,""));});
  try{await sut.PrepareAsync(Serial,apk,null,CancellationToken.None);throw new Exception("failure ignored");}catch(InvalidOperationException){}Check(!calls.Any(a=>a.Contains(forbidden)),failing+" failure blocks "+forbidden);
 }
 static async Task<BlinkAdbResult> Process(string adb,IEnumerable<string> args,CancellationToken token,TimeSpan timeout)
 {
  var start=new ProcessStartInfo(adb){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};foreach(var a in args)start.ArgumentList.Add(a);
  using var process=System.Diagnostics.Process.Start(start)!;var stdout=process.StandardOutput.ReadToEndAsync();var stderr=process.StandardError.ReadToEndAsync();using var deadline=CancellationTokenSource.CreateLinkedTokenSource(token);deadline.CancelAfter(timeout);
  try{await process.WaitForExitAsync(deadline.Token);return new(process.ExitCode,(await stdout)+(await stderr));}catch{try{process.Kill();}catch{}throw;}
 }
 static async Task<int> Emulator(string adb,string apk)
 {
  const string serial="emulator-5580";
  async Task Guard(){var name=await Process(adb,new[]{"-s",serial,"emu","avd","name"},default,TimeSpan.FromSeconds(10));var qemu=await Process(adb,new[]{"-s",serial,"shell","getprop","ro.kernel.qemu"},default,TimeSpan.FromSeconds(10));if(!name.Output.StartsWith("BlinkLink16")||qemu.Output.Trim()!="1")throw new Exception("Dedicated AVD required");}
  await Guard();var revoked=await Process(adb,new[]{"-s",serial,"shell","pm","revoke",BlinkLinkProvisioner.Package,BlinkLinkProvisioner.Permission},default,TimeSpan.FromSeconds(20));Check(revoked.ExitCode==0,"emulator fixture permission revoke");
  var sut=new BlinkLinkProvisioner(async(a,t,d)=>{await Guard();return await Process(adb,a,t,d);});
  var result=await sut.PrepareAsync(serial,Path.GetFullPath(apk),new Progress<string>(Console.WriteLine),default);Check(result.Serial==serial,"real install grant verify and app launch on dedicated AVD");return 0;
 }
}
