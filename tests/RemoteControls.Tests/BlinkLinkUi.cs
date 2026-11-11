using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using ScrcpyGui;

internal static partial class Program
{
 private static IEnumerable<T> BlinkChildren<T>(DependencyObject root)where T:DependencyObject{if(root is T t)yield return t;for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++)foreach(var child in BlinkChildren<T>(VisualTreeHelper.GetChild(root,i)))yield return child;}
 private static void BlinkCapture(Window window,string path){window.UpdateLayout();var root=(FrameworkElement)window.Content;var bitmap=new RenderTargetBitmap((int)root.ActualWidth,(int)root.ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(root);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using var file=File.Create(path);png.Save(file);}
 private static void BlinkPump(int ms){var frame=new DispatcherFrame();var timer=new DispatcherTimer(DispatcherPriority.Background){Interval=TimeSpan.FromMilliseconds(ms)};timer.Tick+=(_,_)=>{timer.Stop();frame.Continue=false;};timer.Start();Dispatcher.PushFrame(frame);}
 private static int FakeBlinkAdb(string[] args){var log=Environment.GetEnvironmentVariable("SCRCPY_GUI_FAKE_BLINK_LOG");if(log!=null)File.AppendAllText(log,string.Join("|",args)+"\n");if(args.Contains("get-state"))Console.WriteLine("device");else if(args.Contains("get-current-user"))Console.WriteLine("0");else if(args.Contains("install"))Console.WriteLine("Success");else if(args.Contains("dumpsys"))Console.WriteLine("Packages:\n  Package [kr.blinklabs.blinklink] (123):\n    install permissions:\n      android.permission.WRITE_SECURE_SETTINGS: granted=true\n    User 0: installed=true");else if(args.Contains("start"))Console.WriteLine("Starting: Intent { cmp=kr.blinklabs.blinklink/.MainActivity }");return 0;}
 private static int BlinkSetupUi()
 {
  var result=Path.Combine(AppContext.BaseDirectory,"blink-ui-result.json");MainWindow? window=null;
  try{
   if(!AppContext.BaseDirectory.StartsWith(@"C:\BackgroundLab\blinklink-",StringComparison.OrdinalIgnoreCase)||!File.Exists(Path.Combine(AppContext.BaseDirectory,"verified-hyperv.txt")))throw new Exception("Verified isolated Hyper-V guest required");
   Environment.SetEnvironmentVariable("SCRCPY_GUI_FAKE_BLINK_ADB","1");Environment.SetEnvironmentVariable("SCRCPY_GUI_FAKE_ADB_ONLINE_AFTER","1");var log=Path.Combine(AppContext.BaseDirectory,"fake-adb.txt");Environment.SetEnvironmentVariable("SCRCPY_GUI_FAKE_BLINK_LOG",log);
   window=new MainWindow(Path.Combine(AppContext.BaseDirectory,"settings"),false);var controls=Get<Dictionary<string,FrameworkElement>>(window,"_controls");((TextBox)controls["adbPath"]).Text=Environment.ProcessPath!;window.Show();BlinkPump(500);
   foreach(var width in new[]{800d,640d}){window.Width=width;window.Height=700;BlinkPump(120);var root=(FrameworkElement)window.Content;var button=BlinkChildren<Button>(root).Single(b=>Equals(b.Content,"Blink Link 설정"));var p=button.TranslatePoint(new Point(),root);Check(button.ActualHeight>=44&&p.X>=0&&p.X+button.ActualWidth<=root.ActualWidth+1&&p.Y+button.ActualHeight<=root.ActualHeight,"Blink toolbar action visible at "+width);}
   BlinkCapture(window,Path.Combine(AppContext.BaseDirectory,"blink-main.png"));Exception? error=null;int phase=0;var deadline=DateTime.UtcNow.AddSeconds(60);var watch=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(100)};
   watch.Tick+=(_,_)=>{Window? dialog=null;try{
    if(DateTime.UtcNow>deadline)throw new Exception("Setup dialog timeout");dialog=window.OwnedWindows.Cast<Window>().FirstOrDefault(w=>w.Title=="Blink Link 준비");if(dialog==null)return;var root=(FrameworkElement)dialog.Content;var combo=BlinkChildren<ComboBox>(root).Single();var install=BlinkChildren<Button>(root).Single(b=>Equals(b.Content,"이 휴대폰에 설치 · 권한 설정"));
    if(phase==0){if(combo.Items.Count==0||!install.IsEnabled)return;Check(combo.SelectedItem!=null,"connected fixture selected without typing serial");var p=install.TranslatePoint(new Point(),root);Check(install.ActualHeight>=56&&p.Y>=0&&p.Y+install.ActualHeight<=root.ActualHeight,"setup action stays in fixed footer");BlinkCapture(dialog,Path.Combine(AppContext.BaseDirectory,"blink-dialog.png"));phase=1;install.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));Check(!combo.IsEnabled&&!install.IsEnabled,"target locked while provisioning");}
    else if(BlinkChildren<TextBlock>(root).Any(t=>t.Text.Contains("설치와 최초 권한 설정을 확인했습니다"))){Check(File.ReadAllLines(log).Where(l=>!string.IsNullOrWhiteSpace(l)).All(l=>l.StartsWith("-s|adb-FAKE1234-abcdef._adb-tls-connect._tcp|")),"all provisioning commands target selected fixture");Check(install.IsEnabled,"action re-enabled after verified success");phase=2;watch.Stop();dialog.Close();}
   }catch(Exception ex){error=ex;watch.Stop();dialog?.Close();}};
   watch.Start();BlinkChildren<Button>((FrameworkElement)window.Content).Single(b=>Equals(b.Content,"Blink Link 설정")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));watch.Stop();if(error!=null)throw error;Check(phase==2,"actual setup click reaches verified completion");window.Close();File.WriteAllText(result,JsonSerializer.Serialize(new{passed=true,assertions=_assertions,machine=Environment.MachineName,mode="Hyper-V guest, fake ADB only"}));return 0;
  }catch(Exception ex){window?.Close();File.WriteAllText(result,JsonSerializer.Serialize(new{passed=false,error=ex.ToString(),assertions=_assertions}));return 1;}
 }
}
