using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Xml.Linq;
using System.Reflection;
using System.Windows.Threading;
using System.Windows.Documents;
using ScrcpyGui;

internal static class Program
{
    private static int _assertions;
    private static void Check(bool condition, string name)
    {
        _assertions++;
        if (!condition) throw new Exception(name);
    }
    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Contains("--pipe-child")) { Thread.Sleep(5000); return 0; }
        if (args.Length == 2 && args[0] == "--spawn-pipe-child")
        {
            var childStart = new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
            childStart.ArgumentList.Add("--pipe-child");
            using var child = System.Diagnostics.Process.Start(childStart)!; File.WriteAllText(args[1], child.Id.ToString()); return 0;
        }
        if (args.Contains("--inventory-ui")) return InventoryUi();
        if (args.Contains("--inventory"))
        {
            foreach (var target in RemoteNative.Enumerate()) Console.WriteLine($"scrcpy PID={target.Pid} HWND=0x{target.Handle:X} 옵션확인={(target.Error.Length == 0 ? "가능" : target.Error)} 보조키={string.Join(',', target.Modifiers)}");
            return 0;
        }
        try
        {
            Layouts(); FitLayouts(); Appearance(); Occlusion(); Persistence(); ScrollTiming(); Activation(); Options(); NativeLayout(); PointerMapping(); RelayCancellation(); UtilityDwell(); MainWindowRegression(args.Contains("--render")); WpfConstruction(args.Contains("--render"));
            Console.WriteLine($"PASS: {_assertions} assertions · 18 layouts × 4 DPI scales, settings, activation, options, WPF construction");
            return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }
    private static void Layouts()
    {
        var target = new PixelRect(800, 400, 400, 800);
        var work = new PixelRect(-1920, -100, 5760, 2260);
        var combinations = 0;
        foreach (var layout in new[] { "split", "combined" })
        foreach (var side in new[] { "left", "right" })
        foreach (var align in new[] { "top", "center", "bottom" })
        foreach (var position in layout == "split" ? new[] { "bottom" } : new[] { "top", "bottom" })
        {
            combinations++;
            foreach (var scale in new[] { 1.0, 1.25, 1.5, 2.0 })
            {
                var s = new RemoteSettings { Layout = layout };
                s.Choice.Side = side; s.Choice.Align = align; s.Choice.ScrollPosition = position;
                var p = RemoteLayout.Calculate(s, target, scale);
                var restored = JsonSerializer.Deserialize<RemoteSettings>(JsonSerializer.Serialize(s))!;
                Check(RemoteLayout.Calculate(restored, target, scale).SequenceEqual(p), "layout survives restart serialization");
                Check(p.Count == 5 && p.Select(b => b.Action).Distinct().Count() == 5, "five actions");
                Check(RemoteLayout.Fits(p, work), "negative origin work area");
                Check(p.All(b => b.Bounds.Right <= target.X || b.Bounds.X >= target.Right || b.Bounds.Y >= target.Bottom), "outside video");
                var vertical = p.Where(b => layout == "combined" || RemoteActivation.Scroll(b.Action)).OrderBy(b => b.Bounds.Y).ToArray();
                var expected = layout == "split" ? new[] { RemoteAction.Up, RemoteAction.Down } : position == "top"
                    ? new[] { RemoteAction.Up, RemoteAction.Down, RemoteAction.Back, RemoteAction.Home, RemoteAction.Recent }
                    : new[] { RemoteAction.Back, RemoteAction.Home, RemoteAction.Recent, RemoteAction.Up, RemoteAction.Down };
                Check(vertical.Select(b => b.Action).SequenceEqual(expected), "order independent of side");
                var top = vertical.First().Bounds.Y; var bottom = vertical.Last().Bounds.Bottom;
                Check(align switch { "top" => top == target.Y, "bottom" => bottom == target.Bottom, _ => (top + bottom) / 2 == target.Y + target.Height / 2 }, "vertical alignment");
                Check(vertical.All(b => side == "left" ? b.Bounds.Right == target.X - s.Distance * scale : b.Bounds.X == target.Right + s.Distance * scale), "DPI distance");
                if (layout == "split")
                {
                    var nav = p.Where(b => !RemoteActivation.Scroll(b.Action)).ToArray();
                    Check(nav[0].Bounds.X + (nav[2].Bounds.Right - nav[0].Bounds.X) / 2 == target.X + target.Width / 2, "bottom nav centered");
                }
            }
        }
        Check(combinations == 18, "all eighteen combinations");
        Check(!RemoteLayout.Fits(RemoteLayout.Calculate(new(), new(0, 0, 300, 800), 1), new(0, 0, 320, 800)), "insufficient room rejected");
        foreach (var scale in new[] { 1.0, 1.5, 2.0 })
        {
            var client = new PixelRect(-1400, 200, 600 * scale, 900 * scale);
            var toolbar = RemoteLayout.Utilities(new(), client, scale);
            Check(toolbar[0].Bounds.X == client.X && toolbar[0].Bounds.Bottom == client.Y - 20 * scale, "toolbar uses configured distance above phone top left");
            Check(toolbar.All(p => p.Bounds.Bottom <= client.Y), "both toolbar buttons stay outside phone content");
        }
        var stacked = RemoteLayout.Utilities(new(), new(200, 300, 100, 600), 1);
        Check(stacked[1].Bounds.X > stacked[0].Bounds.X && stacked[1].Bounds.Y == stacked[0].Bounds.Y, "narrow phone still has both toolbar buttons above it");
    }
    private static void MainWindowRegression(bool render)
    {
        foreach (var argument in new[] { "", "plain", @"C:\my videos\phone.mp4", "embedded\"quote", @"C:\end slash\", "space and slash\\", "한글 경로\\파일.mp4" })
            Check(ScrcpyCommandLine.Parse(ScrcpyCommandLine.Quote(argument)).Single() == argument, "Windows argument quote/parse round trip");
        Check(ScrcpyCommandLine.Parse("--record=\"C:\\my videos\\phone.mp4\"").Single() == @"--record=C:\my videos\phone.mp4", "key equals quoted path is one argument");
        var invalid = false; try { ScrcpyCommandLine.Parse("--record=\"unfinished"); } catch (FormatException) { invalid = true; }
        Check(invalid, "unclosed quote is rejected before apply or launch");
        foreach (var capture in new[] { "--mouse=uhid", "--mouse aoa", "-M", "-fM", "--relative-mouse", "--otg" })
            Check(ScrcpyCommandLine.CapturesPointer(ScrcpyCommandLine.Parse(capture)), "final argument capture mode is recognized");
        foreach (var safe in new[] { "--mouse=sdk", "--mouse=disabled", "--record -M", "-mM", "--window-title -M", "-- --mouse=uhid" })
            Check(!ScrcpyCommandLine.CapturesPointer(ScrcpyCommandLine.Parse(safe)), "option values are not mistaken for capture flags");
        var folder = Path.Combine(AppContext.BaseDirectory, "main-ui-test-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(folder);
        var window = new MainWindow(folder, false);
        try
        {
            var controls = Get<Dictionary<string, FrameworkElement>>(window, "_controls");
            var presets = Get<System.Text.Json.Nodes.JsonObject>(window, "_presets");
            Call(window, "ApplyValues", presets["가로화면"]!);
            Check((string)Call(window, "ReadText", "new-display")! == "1920x1080", "wide preset applied");
            Call(window, "ApplyValues", presets["평소용"]!);
            Check((string)Call(window, "ReadText", "new-display")! == "(기본)", "normal preset clears previous new-display");
            Call(window, "ApplyValues", presets["가볍게"]!); Call(window, "ApplyValues", presets["평소용"]!);
            Check(!(bool)Call(window, "ReadChecked", "turn-screen-off")!, "normal preset clears previous screen-off option");
            var capture = (System.Text.Json.Nodes.JsonObject)Call(window, "CaptureValues", false)!;
            Check(!capture.ContainsKey("__deviceId") && !capture.ContainsKey("__deviceMode"), "preset data excludes device selection");
            Check(!capture.ContainsKey("__presetName"), "preset name belongs to last-session state rather than preset payload");
            var selectedPreset = (System.Windows.Controls.ComboBox)window.FindName("PresetBox");
            selectedPreset.SelectedItem = "고화질";
            Check(File.ReadAllText(Path.Combine(folder, "scrcpy-gui-last.json")).Contains("__presetName"), "choosing preset immediately persists its identity");
            ((System.Windows.Controls.ComboBox)controls["max-size"]).Text = "1600";
            var lastSession = (System.Text.Json.Nodes.JsonObject)Call(window, "CaptureValues", true)!;
            Call(window, "SaveObject", Path.Combine(folder, "scrcpy-gui-last.json"), lastSession);
            var reopened = new MainWindow(folder, false);
            try
            {
                Check(Equals(((System.Windows.Controls.ComboBox)reopened.FindName("PresetBox")).SelectedItem, "고화질"), "restarting restores actual selected preset item");
                Check((string)Call(reopened, "ReadText", "max-size")! == "1600", "restored preset identity does not overwrite later manual adjustments");
            }
            finally { reopened.Close(); }
            foreach (var name in new[] { "removed-preset", "" })
            {
                lastSession["__presetName"] = name;
                Call(window, "SaveObject", Path.Combine(folder, "scrcpy-gui-last.json"), lastSession);
                var fallback = new MainWindow(folder, false);
                try { Check(Equals(((System.Windows.Controls.ComboBox)fallback.FindName("PresetBox")).SelectedItem, "(선택 안 함)") && (string)Call(fallback, "ReadText", "max-size")! == "1600", "deleted or cleared preset falls back without losing last options"); }
                finally { fallback.Close(); }
            }
            selectedPreset.SelectedItem = "(선택 안 함)";
            Check((string?)System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(Path.Combine(folder, "scrcpy-gui-last.json")))!["__presetName"] == "", "explicitly clearing preset selection is persisted");
            foreach (var pair in controls)
            {
                Check(!string.IsNullOrWhiteSpace(System.Windows.Automation.AutomationProperties.GetName(pair.Value)), "every input has an accessibility name");
                if (pair.Value is System.Windows.Controls.CheckBox box) Check(box.Content is string { Length: > 0 } && box.MinHeight >= 44, "checkbox has a labeled full-height click target");
            }
            var fakePath = Path.Combine(folder, "custom-scrcpy.exe"); File.WriteAllText(fakePath, "not executed");
            ((System.Windows.Controls.TextBox)controls["scrcpyPath"]).Text = fakePath;
            Check(Get<string>(window, "_scrcpyPath") == fakePath, "valid manual executable path outranks automatic installations");
            Check(!(bool)Call(window, "SaveObject", Path.Combine(folder, "missing", "settings.json"), capture)!, "write failure is returned");
            Check(((System.Windows.Controls.TextBlock)window.FindName("StatusText")).Text.Contains("저장 실패"), "write failure appears in status");
            Check((bool)Call(window, "SaveObject", Path.Combine(folder, "saved.json"), capture)!, "successful atomic save clears failure");
            var presetBox = (System.Windows.Controls.ComboBox)window.FindName("PresetBox"); presetBox.Text = "실패 저장";
            using (var locked = new FileStream(Path.Combine(folder, "scrcpy-gui-presets.json"), FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                Call(window, "SavePresetButton_OnClick", window, new RoutedEventArgs());
                Check(!Get<System.Text.Json.Nodes.JsonObject>(window, "_presets").ContainsKey("실패 저장"), "failed preset save does not commit memory state");
            }
            Check((bool)Call(window, "SaveObject", Path.Combine(folder, "other.json"), capture)! && Get<string>(window, "_persistenceError").Contains("저장 실패"), "unrelated successful save does not erase failed preset warning");
            Check((bool)Call(window, "SaveObject", Path.Combine(folder, "scrcpy-gui-presets.json"), Get<System.Text.Json.Nodes.JsonObject>(window, "_presets"))! && Get<string>(window, "_persistenceError").Length == 0, "retrying failed file clears warning only after success");
            Call(window, "ReloadPresetList", "평소용"); Call(window, "SetStatus", "설정 준비됨 · 실행할 휴대폰을 연결하세요.");
            var root = (FrameworkElement)window.Content;
            var definitions = Get<Dictionary<string, OptionDefinition>>(window, "_definitions");
            var navigation = (System.Windows.Controls.ListBox)window.FindName("NavigationList");
            foreach (var size in new[] { new Size(640, 650), new Size(1080, 900), new Size(640, 650) })
            foreach (var group in definitions.Values.Select(d => d.Group).Distinct())
            {
                navigation.SelectedItem = navigation.Items.OfType<System.Windows.Controls.ListBoxItem>().Single(i => Equals(i.Tag, group));
                root.Measure(size); root.Arrange(new Rect(new Point(0, 0), size)); root.UpdateLayout();
                var tabs = (System.Windows.Controls.TabControl)window.FindName("OptionTabs");
                var viewport = (System.Windows.Controls.ScrollViewer)((System.Windows.Controls.TabItem)tabs.SelectedItem).Content;
                var page = (FrameworkElement)viewport.Content;
                Check(page.ActualWidth >= viewport.ViewportWidth - 10 && page.ActualWidth <= viewport.ViewportWidth, "option page follows actual viewport through narrow-wide-narrow resizing");
                foreach (var name in new[] { "DeviceBox", "RefreshButton", "DiscoverButton", "RunButton" })
                {
                    var element = (FrameworkElement)window.FindName(name); var p = element.TranslatePoint(new Point(0, 0), root);
                    Check(p.X >= 0 && p.X + element.ActualWidth <= size.Width + 1 && p.Y >= 0 && p.Y + element.ActualHeight <= size.Height + 1, "connection and launch actions stay inside narrow and regular viewports");
                }
                if (render)
                {
                    var bitmap = new RenderTargetBitmap((int)size.Width, (int)size.Height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(root);
                    var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using var file = File.Create(Path.Combine(AppContext.BaseDirectory, $"main-{group}-{size.Width}.png")); encoder.Save(file);
                }
            }
            var runProcess = typeof(MainWindow).GetMethod("RunProcessAsync", BindingFlags.Static | BindingFlags.NonPublic)!;
            object RunFake(string exe, string[] arguments, CancellationToken token, TimeSpan timeout)
            {
                var task = (Task)runProcess.Invoke(null, [exe, arguments, token, timeout])!; task.GetAwaiter().GetResult();
                return task.GetType().GetProperty("Result")!.GetValue(task)!;
            }
            int Code(object result) => (int)result.GetType().GetProperty("ExitCode")!.GetValue(result)!;
            var cmd = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
            Check(Code(RunFake(cmd, ["/d", "/c", "exit 7"], CancellationToken.None, TimeSpan.FromSeconds(3))) == 7, "process failure exit code is preserved");
            var powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            Check(Code(RunFake(powershell, ["-NoProfile", "-NonInteractive", "-Command", "Start-Sleep -Seconds 5"], CancellationToken.None, TimeSpan.FromMilliseconds(150))) == -2, "hung test command times out");
            using var cancel = new CancellationTokenSource(150);
            var cancelled = RunFake(powershell, ["-NoProfile", "-NonInteractive", "-Command", "Start-Sleep -Seconds 5"], cancel.Token, TimeSpan.FromSeconds(3));
            Check(Code(cancelled) == -2 && ((string)cancelled.GetType().GetProperty("Output")!.GetValue(cancelled)!).Contains("취소"), "test command can be cancelled separately from timeout");
            var childIdPath = Path.Combine(folder, "pipe-child.pid");
            try
            {
                var pipe = RunFake(Environment.ProcessPath!, ["--spawn-pipe-child", childIdPath], CancellationToken.None, TimeSpan.FromMilliseconds(1500));
                Check(File.Exists(childIdPath) && Code(pipe) == -2, "timeout covers inherited stdout held by a child after direct process exits");
            }
            finally
            {
                if (File.Exists(childIdPath))
                {
                    try { using var child = System.Diagnostics.Process.GetProcessById(int.Parse(File.ReadAllText(childIdPath))); if (!child.HasExited) child.Kill(); } catch (ArgumentException) { }
                }
            }
            var session = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(cmd) { Arguments = "/d /c exit 7", UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true })!;
            Set(window, "_sessionProcess", session);
            var dispatcher = Dispatcher.CurrentDispatcher; var oldContext = SynchronizationContext.Current;
            SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(dispatcher));
            try
            {
                var monitor = (Task)Call(window, "MonitorSessionAsync", session, false)!;
                if (!monitor.IsCompleted)
                {
                    var frame = new DispatcherFrame(); _ = monitor.ContinueWith(_ => dispatcher.BeginInvoke(new Action(() => frame.Continue = false))); Dispatcher.PushFrame(frame);
                }
                monitor.GetAwaiter().GetResult();
                Check(((System.Windows.Controls.TextBlock)window.FindName("SessionStatusText")).Text.Contains("실패 · 종료 코드 7"), "early session exit is reported as failure instead of launched");
            }
            finally { SynchronizationContext.SetSynchronizationContext(oldContext); }
        }
        finally { window.Close(); Directory.Delete(folder, true); }
    }
    private static void FitLayouts()
    {
        foreach (var layout in new[] { "split", "combined" })
        foreach (var side in new[] { "left", "right" })
        foreach (var align in new[] { "top", "center", "bottom" })
        foreach (var position in layout == "split" ? new[] { "bottom" } : new[] { "top", "bottom" })
        foreach (var scale in new[] { 1.0, 1.5, 2.0 })
        foreach (var work in new[] { new PixelRect(0, 0, 1920, 1040), new PixelRect(-1920, 0, 1920, 1040) })
        {
            var s = new RemoteSettings { Layout = layout };
            s.Choice.Side = side; s.Choice.Align = align; s.Choice.ScrollPosition = position;
            var original = new PixelRect(work.X - 30, work.Y - 20, 420 * scale, 1200 * scale);
            var chromeW = 16 * scale; var chromeH = 40 * scale;
            var fit = RemoteLayout.FitTarget(s, original, work, scale, chromeW, chromeH);
            Check(fit is not null, "all eighteen layouts fit large phone to monitor");
            var fitted = fit!.Value;
            Check(RemoteLayout.Fits(RemoteLayout.Calculate(s, fitted, scale).Concat(RemoteLayout.Utilities(s, fitted, scale)), work), "all seven controls remain visible after fitting");
            Check(fitted.X >= work.X && fitted.Y >= work.Y && fitted.Right <= work.Right && fitted.Bottom <= work.Bottom, "phone remains inside work area");
            var beforeAspect = (original.Width - chromeW) / (original.Height - chromeH);
            var afterAspect = (fitted.Width - chromeW) / (fitted.Height - chromeH);
            Check(Math.Abs(afterAspect / beforeAspect - 1) < .015, "automatic resize preserves video aspect including title bar");
        }
        var phone = new PixelRect(600, 200, 400, 700);
        Check(RemoteLayout.FitTarget(new(), phone, new(0, 0, 1920, 1040), 1) == phone, "already fitting phone does not move or resize");
        Check(RemoteLayout.FitTarget(new(), phone, new(0, 0, 100, 100), 1) is null, "impossible monitor does not shrink controls into unusable sizes");
    }
    private static void Persistence()
    {
        var folder = Path.Combine(AppContext.BaseDirectory, "settings-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, "remote.json");
        try
        {
            var s = new RemoteSettings(); s.Split.Side = "left"; s.Split.Align = "bottom";
            s.Combined.Side = "right"; s.Combined.Align = "top"; s.Combined.ScrollPosition = "top";
            s.Save(path); var original = File.ReadAllText(path);
            s.Layout = "combined"; s.Save(path);
            var r = RemoteSettings.Load(path);
            Check(r.Choice.ScrollPosition == "top" && r.Choice.Align == "top", "combined restored");
            r.Layout = "split"; Check(r.Choice.Side == "left" && r.Choice.Align == "bottom", "split selection retained");
            Check(File.ReadAllText(path + ".bak") == original, "backup preserved");
            File.WriteAllText(path, "{\"DwellMs\":700,\"RepeatMs\":450,\"ArrivalMs\":60,\"AfterMs\":60,\"TargetHint\":\"phone\",\"U\":0.3}");
            r = RemoteSettings.Load(path);
            Check(r.ScrollMode == "atomic" && r.DwellMs == 300 && r.RepeatMs == 300 && r.SettleMs == 20 && r.TargetHint == "phone" && r.U == .3, "legacy stock speed upgrades while target and scroll point survive");
            File.WriteAllText(path, "{\"DwellMs\":900,\"RepeatMs\":120}");
            r = RemoteSettings.Load(path);
            Check(r.DwellMs == 900 && r.RepeatMs == 120, "legacy custom timings survive upgrade");
            r.ScrollMode = "staged"; r.DwellMs = r.RepeatMs = r.ArrivalMs = r.AfterMs = r.SettleMs = 0; r.Save(path);
            r = RemoteSettings.Load(path);
            Check(r.ScrollMode == "staged" && r.DwellMs == 0 && r.RepeatMs == 0 && r.ArrivalMs == 0 && r.AfterMs == 0 && r.SettleMs == 0, "all zero timing settings and selected route survive restart");
            File.WriteAllText(path, "{\"Size\":999,\"U\":-2,\"Split\":null}");
            r = RemoteSettings.Load(path); Check(r.Size == 200 && r.U == 0 && r.Split is not null, "invalid values normalized");
            File.WriteAllText(path, "{\"Version\":99}");
            var rejected = false; try { RemoteSettings.Load(path); } catch (InvalidDataException) { rejected = true; }
            Check(rejected, "future version preserved, not overwritten");
        }
        finally { foreach (var f in Directory.GetFiles(folder)) File.Delete(f); Directory.Delete(folder); }
    }
    private static void Appearance()
    {
        foreach (var scale in new[] { 1.0, 1.25, 1.5, 2.0 })
        foreach (var mode in new[] { "fixed", "relative" })
        foreach (var ratio in new[] { 50, 100, 180, 250 })
        foreach (var layout in new[] { "split", "combined" })
        {
            var s = new RemoteSettings { SizeMode = mode, WidthPercent = ratio, Layout = layout, Gap = 0, Distance = 0, GroupGap = 0 };
            var phone = new PixelRect(-800, 200, 400 * scale, 800 * scale);
            var p = RemoteLayout.Calculate(s, phone, scale).Concat(RemoteLayout.Utilities(s, phone, scale)).ToArray();
            Check(p.All(b => Math.Abs(b.Bounds.Width / b.Bounds.Height - ratio / 100.0) < .00001), "all seven buttons use configured rectangular ratio at every DPI");
            Check(p.All(b => b.Bounds.Right <= phone.X || b.Bounds.X >= phone.Right || b.Bounds.Bottom <= phone.Y || b.Bounds.Y >= phone.Bottom), "zero margin never overlaps phone interior");
            if (mode == "relative")
            {
                var before = RemoteLayout.ButtonSize(s, phone, scale);
                var after = RemoteLayout.ButtonSize(s, phone with { Width = phone.Width * 1.5 }, scale);
                Check(Math.Abs(after.Height / before.Height - 1.5) < .00001, "relative sizing follows mirror resize once without double DPI scaling");
            }
        }
        var invalid = new RemoteSettings { WidthPercent = 999, FontColor = "bad", BackgroundColor = null!, GaugePattern = "unknown", FontSize = 999, ButtonOpacity = 0 };
        invalid.Normalize();
        Check(invalid.WidthPercent == 250 && invalid.FontSize == 48 && invalid.ButtonOpacity == 25 && invalid.FontColor == "#FFFFFF" && invalid.BackgroundColor == "#18202E" && invalid.GaugePattern == "bar", "invalid appearance settings normalize safely");
        var custom = new RemoteSettings { WidthPercent = 150, SizeMode = "relative", RelativeSizePercent = 22, FontColor = "#ffd75e", BackgroundColor = "#101010", GaugePattern = "ring", FontSize = 22, GaugeThickness = 8, CompletionColor = "#B18CFF" };
        var restored = JsonSerializer.Deserialize<RemoteSettings>(JsonSerializer.Serialize(custom))!;
        restored.Normalize();
        Check(restored.FontColor == "#FFD75E" && restored.WidthPercent == 150 && restored.SizeMode == "relative" && restored.GaugePattern == "ring" && restored.CompletionColor == custom.CompletionColor, "appearance, relative sizing and feedback survive serialization");
        foreach (var pattern in new[] { "bar", "ring", "fill", "none" })
        foreach (var progress in new[] { 0.0, .5, 1.0 })
        {
            custom.GaugePattern = pattern;
            var visual = new RemoteButtonVisual { Width = 144, Height = 96 };
            visual.Paint(custom, RemoteAction.Down, progress, true, true);
            visual.Measure(new Size(144, 96)); visual.Arrange(new Rect(0, 0, 144, 96)); visual.UpdateLayout();
            var gauge = Get<System.Windows.Shapes.Path>(visual, "_ring");
            var fill = Get<System.Windows.Controls.Border>(visual, "_fill");
            var bar = Get<System.Windows.Controls.Border>(visual, "_bar");
            Check((gauge.Visibility == Visibility.Visible) == (pattern == "ring") && (fill.Visibility == Visibility.Visible) == (pattern == "fill") && (bar.Visibility == Visibility.Visible) == (pattern == "bar"), "only chosen gauge pattern is visible");
            Check(Get<System.Windows.Controls.TextBlock>(visual, "_caption").FontSize == 22, "configured font size reaches real shared visual");
            if (pattern == "ring") Check((gauge.Data is not null) == (progress > 0), "ring has empty, arc and complete geometries");
            visual.Paint(custom, RemoteAction.Down, 0, true, true, true);
            Check(((SolidColorBrush)Get<System.Windows.Controls.Border>(visual, "_surface").Background).Color == RemoteButtonVisual.Brush(custom.CompletionColor).Color, "completion feedback uses selected color");
        }
    }
    private static void ScrollTiming()
    {
        var settings = new RemoteSettings();
        Check(settings.ScrollMode == "atomic" && settings.DwellMs == 300 && settings.RepeatMs == 300 && settings.SettleMs == 20, "new-alt optimized defaults");
        settings.DwellMs = settings.RepeatMs = settings.SettleMs = settings.ArrivalMs = settings.AfterMs = 0;
        settings.Normalize();
        Check(settings.DwellMs == 0 && settings.RepeatMs == 0 && settings.SettleMs == 0 && settings.ArrivalMs == 0 && settings.AfterMs == 0, "zero delays are configurable and retained");
        var activation = new RemoteActivation(); activation.Observe(RemoteAction.Up, 0, 0);
        Check(activation.Due(0, settings, false) && double.IsFinite(activation.Progress(0, 0)), "zero dwell starts immediately with finite gauge");
        var pulses = new List<(RemoteNative.Point Target, int Delta, RemoteNative.Point Restore)>();
        using var relay = new RemoteRelay(false, _ => throw new Exception("atomic settle must not move cursor again"), _ => 0, (t, d, r) => pulses.Add((t, d, r)));
        settings.Notches = 3; settings.SettleMs = 20;
        var config = new RelayConfiguration(null, settings, [], default, default, true, 1);
        Set(relay, "_running", config); Set(relay, "_active", RemoteAction.Down);
        Set(relay, "_destination", new RemoteNative.Point(-500, 800)); Set(relay, "_logical", new RemoteNative.Point(300, 200));
        Call(relay, "StartAtomic", config);
        Check(pulses.Count == 1 && pulses[0].Delta == -360 && pulses[0].Target.X == -500 && pulses[0].Restore.X == 300, "atomic scroll sends destination, amount and original gaze in one pulse");
        var deadline = Get<long>(relay, "_deadline");
        Call(relay, "Advance", deadline - 1);
        Check(Get<int>(relay, "_phase") == 3 && Get<int>(relay, "_completed") == 0, "settle wait holds before repeat starts");
        Call(relay, "Advance", deadline);
        Check(Get<int>(relay, "_phase") == 0 && Get<int>(relay, "_completed") == 1, "atomic completion does not perform delayed cursor restore");
        settings.SettleMs = 0; Call(relay, "StartAtomic", config);
        Check(Get<int>(relay, "_phase") == 0 && Get<int>(relay, "_completed") == 2, "zero settle completes without extra timer tick");
        settings.SettleMs = 20; Call(relay, "StartAtomic", config); Call(relay, "Cancel", "covered");
        Check(Get<int>(relay, "_phase") == 0 && Get<RelayConfiguration?>(relay, "_running") is null, "occlusion cancels atomic settle without replay or cursor snap");
        var batch = (Array)typeof(RemoteNative).GetMethod("CreateWheelPulse", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null,
            [new RemoteNative.Point(-500, 800), -360, new RemoteNative.Point(300, 200)])!;
        object Mouse(int i) { var input = batch.GetValue(i)!; var union = input.GetType().GetField("Union")!.GetValue(input)!; return union.GetType().GetField("Mouse")!.GetValue(union)!; }
        T Field<T>(object o, string name) => (T)o.GetType().GetField(name)!.GetValue(o)!;
        Check(batch.Length == 3 && Field<uint>(Mouse(0), "Flags") == 0xC001 && Field<uint>(Mouse(1), "Flags") == 0x800 && Field<uint>(Mouse(2), "Flags") == 0xC001, "native batch order is absolute move, wheel, restore");
        Check(Field<uint>(Mouse(1), "Data") == unchecked((uint)-360) && Enumerable.Range(0, 3).All(i => Field<nuint>(Mouse(i), "Extra") == RemoteNative.Tag), "signed wheel delta and own-hook tag preserved for whole batch");
    }
    private static void Occlusion()
    {
        Check(RemoteNative.IsAssistiveSurface(0x08000008), "non-activating topmost input panel must not hide mirror controls");
        Check(RemoteNative.IsAssistiveSurface(0x80020), "click-through layered input surface must not hide mirror controls");
        Check(!RemoteNative.IsAssistiveSurface(0) && !RemoteNative.IsAssistiveSurface(0x80000), "ordinary and layered application windows still count as cover");
        var phone = new PixelRect(100, 100, 400, 800);
        var ignored = new nint[] { 77, 88 };
        var calls = 0;
        Check(!RemoteNative.CoversIntersection(phone, new(700, 100, 300, 300), 11, ignored, _ => { calls++; return 99; }) && calls == 0,
            "non-overlapping foreground window does not hide overlays");
        Check(RemoteNative.CoversIntersection(phone, phone, 11, ignored, _ => 99), "window covering whole mirror hides overlays");
        Check(RemoteNative.CoversIntersection(phone, new(499, 200, 20, 50), 11, ignored, _ => 99), "thin partial cover is detected at its intersection");
        Check(!RemoteNative.CoversIntersection(phone, phone, 11, ignored, _ => 11), "transparent accessibility surface does not cover actual mirror hit target");
        Check(!RemoteNative.CoversIntersection(phone, phone, 11, ignored, _ => 77), "own logical cursor is excluded from cover detection");
        Check(!RemoteNative.CoversIntersection(phone, phone, 11, ignored, _ => 88), "own control window is excluded from cover detection");
        Check(!RemoteNative.CoversIntersection(phone, phone, 11, ignored, _ => 0), "unavailable hit result is not fabricated into occlusion");
        Check(!RemoteNative.CoversIntersection(phone, new(500, 100, 20, 300), 11, ignored, _ => 99), "adjacent window without overlap does not hide controls");
    }
    private static void Activation()
    {
        var s = new RemoteSettings { DwellMs = 700, RepeatMs = 450 };
        var a = new RemoteActivation();
        foreach (var action in new[] { RemoteAction.Back, RemoteAction.Home, RemoteAction.Recent })
        {
            a.Reset(); a.Observe(action, 0, s.DwellMs);
            Check(!a.Due(699, s, false) && a.Due(700, s, false), "dwell threshold");
            a.Fired(); a.Completed(800, s.RepeatMs);
            Check(!a.Due(999999, s, false), "nav never repeats");
        }
        a.Reset(); a.Observe(RemoteAction.Down, 0, 700);
        long now = 700;
        for (var i = 0; i < 50; i++)
        {
            Check(a.Due(now, s, false), "scroll ready"); a.Fired();
            Check(!a.Due(now + 10000, s, false), "busy has no queued repeat");
            now += 120; a.Completed(now, 450);
            Check(Math.Abs(a.Progress(now + 225, 700, 450) - .5) < .00001, "repeat feedback fills against repeat interval rather than first dwell time");
            Check(!a.Due(now + 449, s, false), "repeat after completion only"); now += 450;
        }
        a.Observe(null, now, 700); Check(!a.Due(now + 10000, s, false), "leave stops");
        a.Observe(RemoteAction.Up, now, 700); Check(!a.Due(now + 699, s, false), "fresh dwell after reentry");
        s.Activation = "click"; Check(!a.Due(now + 700, s, false), "click mode has no dwell");
        s.HoldRepeat = true; a.Fired(); a.Completed(now, 450);
        Check(a.Due(now + 450, s, true) && !a.Due(now + 450, s, false), "hold repeat stops on release");
        foreach (var dwellRepeat in new[] { false, true })
        foreach (var holdRepeat in new[] { false, true })
        foreach (var action in new[] { RemoteAction.Up, RemoteAction.Down, RemoteAction.Home })
        {
            s.Repeat = dwellRepeat; s.HoldRepeat = holdRepeat;
            a.Reset(); a.Observe(action, 0, 700); a.Fired(); a.Completed(100, 450);
            Check(a.Due(550, s, true) == (holdRepeat && RemoteActivation.Scroll(action)), "click hold independent of dwell repeat");
            Check(!a.Due(550, s, false), "released click never repeats");
        }
        a.Reset(); Check(!a.Due(long.MaxValue - 1, s, true), "stop has no stale activation");
    }
    private static void Options()
    {
        Check(RemoteNative.ParseOptions("scrcpy.exe").Modifiers.SequenceEqual(new ushort[] { 0xA4 }), "default LeftAlt");
        Check(RemoteNative.ParseOptions("\"C:\\Program Files\\scrcpy.exe\" --shortcut-mod=rctrl+lsuper,lalt").Modifiers.SequenceEqual(new ushort[] { 0xA3, 0x5B }), "actual modifier combo");
        Check(RemoteNative.ParseOptions("scrcpy.exe --shortcut-mod ralt").Modifiers.SequenceEqual(new ushort[] { 0xA5 }), "separated modifier");
        foreach (var option in new[] { "--no-control", "-n", "--mouse=uhid", "--mouse=aoa", "--mouse disabled", "--otg", "-M", "-fn", "-nf", "-fM", "-KM", "-fnS", "--shortcut-mod=invalid" })
            Check(RemoteNative.ParseOptions("scrcpy.exe " + option).Error.Length > 0, "unsafe option " + option);
        foreach (var option in new[] { "-fsphoneMn", "-s phoneMn", "-fr movieMn.mp4", "--serial -fM", "--window-title -fn", "--record=-fM", "--window-title=\"phone name\" --shortcut-mod=\"rctrl+lsuper\"" })
            Check(RemoteNative.ParseOptions("scrcpy.exe " + option).Error.Length == 0, "option value is not a flag " + option);
        Check(RemoteNative.ParseOptions("scrcpy.exe --window-title=\"phone name\" --shortcut-mod=\"rctrl+lsuper\"").Modifiers.SequenceEqual(new ushort[] { 0xA3, 0x5B }), "Windows quoted option value");
        Check(RemoteNative.ParseOptions("").Error.Length > 0, "unreadable options block");
    }
    private static void NativeLayout()
    {
        var native = typeof(RemoteNative);
        var flags = System.Reflection.BindingFlags.NonPublic;
        Check(Marshal.SizeOf(native.GetNestedType("Input", flags)!) == (IntPtr.Size == 8 ? 40 : 28), "SendInput native ABI");
        Check(Marshal.SizeOf<RemoteNative.HookData>() == (IntPtr.Size == 8 ? 32 : 24), "mouse hook ABI");
        Check(RemoteNative.ReadCommandLine(Environment.ProcessId).Contains("RemoteControls.Tests", StringComparison.OrdinalIgnoreCase), "read actual process command line");
    }
    private static void PointerMapping()
    {
        var point = RemoteRelay.ObserveMovement(new(150, 200), new(600, 700), new(900, 1000), true, 1);
        Check(point.X == 600 && point.Y == 700, "external synthetic gaze remains absolute during excursion");
        point = RemoteRelay.ObserveMovement(point, new(905, 994), new(900, 1000), true, 0);
        Check(point.X == 605 && point.Y == 694, "physical delta applied to latest logical position");
        point = RemoteRelay.ObserveMovement(point, new(-1300, 80), new(900, 1000), false, 0);
        Check(point.X == -1300 && point.Y == 80, "normal cursor movement on negative monitor");
        var video = new PixelRect(-1400, 100, 600, 900);
        Check(RemoteLayout.ScrollPoint(video, .5, .5) == (-1100, 550), "relative video point");
        Check(RemoteLayout.ScrollPoint(video, 1, 1) == (-801, 999), "edge coordinates remain inside video");
        Check(RemoteLayout.ScrollPoint(new(120.5, 77.5, 600, 900), 0, 0) == (121, 78), "fractional calibration edge");
    }
    private static void WpfConstruction(bool render)
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var owner = new Window();
        var settingsDirectory = Path.Combine(AppContext.BaseDirectory, "ui-settings-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(settingsDirectory);
        using (var controls = new RemoteControls(owner, settingsDirectory, () => { }))
        {
            var timing = Get<System.Windows.Controls.StackPanel>(controls, "_scrollSettings");
            Check(NumberInputs(timing).Count() == 4, "atomic settings expose dwell, repeat, amount and settle");
            var mode = timing.Children.OfType<System.Windows.Controls.ComboBox>().Single();
            mode.SelectedIndex = 1;
            Check(NumberInputs(timing).Count() == 5 && Get<RemoteSettings>(controls, "_settings").ScrollMode == "staged", "staged settings expose independent arrival and after timings");
            var dwellInput = NumberInputs(timing).First();
            dwellInput.Text = "127";
            dwellInput.RaiseEvent(new System.Windows.Input.KeyboardFocusChangedEventArgs(System.Windows.Input.Keyboard.PrimaryDevice, 0, dwellInput, null) { RoutedEvent = System.Windows.Input.Keyboard.LostKeyboardFocusEvent });
            Check(Get<RemoteSettings>(controls, "_settings").DwellMs == 127, "exact numeric input applies non-preset timing");
            Check(Get<System.Windows.Controls.TextBlock>(controls, "_scrollSummary").Text.Contains("127ms"), "timing summary reflects edited input");
            var settingsTabs = Get<System.Windows.Controls.TabControl>(controls, "_settingsTabs");
            Check(settingsTabs.Items.Cast<System.Windows.Controls.TabItem>().Select(t => t.Header).SequenceEqual(new[] { "사용", "배치·크기", "글자·색상", "드웰 피드백", "속도·스크롤", "고급" }), "settings are split into six focused tabs");
            var appearanceBody = (System.Windows.Controls.StackPanel)((System.Windows.Controls.TabItem)settingsTabs.Items[2]).Content;
            var colorEditor = appearanceBody.Children.OfType<System.Windows.Controls.Grid>().SelectMany(g => g.Children.OfType<System.Windows.Controls.StackPanel>()).First(p => p.Children.OfType<System.Windows.Controls.ComboBox>().Any());
            var palette = colorEditor.Children.OfType<System.Windows.Controls.ComboBox>().Single();
            palette.SelectedIndex = 7;
            Check(Get<RemoteSettings>(controls, "_settings").FontColor == "#FFD75E", "named color palette applies font color");
            var hexInput = colorEditor.Children.OfType<System.Windows.Controls.TextBox>().Single();
            hexInput.Text = "#123456";
            hexInput.RaiseEvent(new System.Windows.Input.KeyboardFocusChangedEventArgs(System.Windows.Input.Keyboard.PrimaryDevice, 0, hexInput, null) { RoutedEvent = System.Windows.Input.Keyboard.LostKeyboardFocusEvent });
            Check(Get<RemoteSettings>(controls, "_settings").FontColor == "#123456" && palette.SelectedIndex == 11, "custom RGB input applies without palette overriding it");
            hexInput.Text = "invalid";
            hexInput.RaiseEvent(new System.Windows.Input.KeyboardFocusChangedEventArgs(System.Windows.Input.Keyboard.PrimaryDevice, 0, hexInput, null) { RoutedEvent = System.Windows.Input.Keyboard.LostKeyboardFocusEvent });
            Check(hexInput.Text == "#123456" && Get<RemoteSettings>(controls, "_settings").FontColor == "#123456", "invalid custom color preserves current value");
            var layoutForm = Get<System.Windows.Controls.StackPanel>(controls, "_form");
            var ratioInput = NumberInputs(layoutForm).Single(t => ((string)t.Tag).StartsWith("가로 비율"));
            ratioInput.Text = "150";
            ratioInput.RaiseEvent(new System.Windows.Input.KeyboardFocusChangedEventArgs(System.Windows.Input.Keyboard.PrimaryDevice, 0, ratioInput, null) { RoutedEvent = System.Windows.Input.Keyboard.LostKeyboardFocusEvent });
            Check(RemoteLayout.ButtonSize(Get<RemoteSettings>(controls, "_settings"), new(0, 0, 400, 800), 1) == (108, 72), "numeric width ratio affects actual layout geometry");
            layoutForm.Children.OfType<System.Windows.Controls.ComboBox>().Last().SelectedIndex = 1;
            Check(Get<RemoteSettings>(controls, "_settings").SizeMode == "relative" && NumberInputs(layoutForm).Any(t => ((string)t.Tag).StartsWith("창 너비 대비")), "size mode selector exposes window-relative size setting");
            Check(controls.Page is System.Windows.Controls.Grid, "WPF settings page constructed");
            var darkTab = new System.Windows.Controls.TabItem { Foreground = Brushes.Black, Content = controls.Page };
            var darkTabs = new System.Windows.Controls.TabControl { Foreground = Brushes.Black };
            darkTabs.Items.Add(darkTab); owner.Content = darkTabs;
            darkTabs.Measure(new Size(720, 950)); darkTabs.Arrange(new Rect(0, 0, 720, 950)); darkTabs.UpdateLayout();
            var body = (System.Windows.Controls.StackPanel)((System.Windows.Controls.ScrollViewer)((System.Windows.Controls.Grid)controls.Page).Children[0]).Content;
            var pageTitle = (System.Windows.Controls.TextBlock)body.Children[0];
            Check(pageTitle.Foreground.ToString() == Brushes.Gainsboro.ToString(), "page text stays readable when TabItem inherits black foreground");
            darkTab.Content = null; darkTabs.Items.Clear(); owner.Content = null;
            Check(!controls.KeepRunningWhenSettingsClosed, "unattached settings window can exit normally");
            owner.WindowState = WindowState.Minimized;
            controls.RestoreOwnerState();
            Check(owner.WindowState == WindowState.Normal, "settings restores minimized normal window");
            owner.WindowState = WindowState.Maximized;
            // A headless Window has no HWND, so WPF does not raise the native
            // StateChanged event. Invoke the same subscribed handler explicitly.
            Call(controls, "OwnerStateChanged", owner, EventArgs.Empty);
            owner.WindowState = WindowState.Minimized;
            controls.RestoreOwnerState();
            Check(owner.WindowState == WindowState.Maximized, "settings preserves previous maximized state");
            owner.WindowState = WindowState.Normal;
            var readyDeadline = Environment.TickCount64 + 2000;
            var worker = Get<RemoteRelay>(controls, "_relay");
            while (!worker.View.InputReady && Environment.TickCount64 < readyDeadline) Thread.Sleep(10);
            Check(worker.View.InputReady, "native hook and message timer are ready before enabling controls");
            RefreshedTargets(controls);
            LostTarget(controls);
            if (render)
            {
                var source = XDocument.Load(Path.Combine(AppContext.BaseDirectory, "MainWindow.source.xaml"));
                XNamespace wpf = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
                var dictionary = new XElement(wpf + "ResourceDictionary", new XAttribute(XNamespace.Xmlns + "x", "http://schemas.microsoft.com/winfx/2006/xaml"), source.Root!.Element(wpf + "Window.Resources")!.Elements());
                owner.Resources = (ResourceDictionary)XamlReader.Parse(dictionary.ToString());
                owner.Background = new SolidColorBrush(Color.FromRgb(13, 13, 14)); owner.Foreground = Brushes.White;
                owner.FontFamily = new FontFamily("Segoe UI, 맑은 고딕");
                var border = new System.Windows.Controls.Border { Background = owner.Background, Child = controls.Page };
                owner.Content = border;
                border.Measure(new Size(720, 950)); border.Arrange(new Rect(0, 0, 720, 950)); border.UpdateLayout();
                var bitmap = new RenderTargetBitmap(720, 950, 96, 96, PixelFormats.Pbgra32); bitmap.Render(border);
                var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                var output = Path.Combine(AppContext.BaseDirectory, "remote-settings.png");
                using var file = File.Create(output); encoder.Save(file);
                Console.WriteLine("WPF render: " + output);
                for (var tabIndex = 0; tabIndex < settingsTabs.Items.Count; tabIndex++)
                {
                    settingsTabs.SelectedIndex = tabIndex;
                    var preview = Get<RemoteButtonVisual>(controls, "_stylePreview");
                    preview.Paint(Get<RemoteSettings>(controls, "_settings"), RemoteAction.Down, .65, true, true);
                    Get<RemoteButtonVisual>(controls, "_appearancePreview").Paint(Get<RemoteSettings>(controls, "_settings"), RemoteAction.Down, 0, false, true);
                    border.Measure(new Size(720, 950)); border.Arrange(new Rect(0, 0, 720, 950)); border.UpdateLayout();
                    Check(settingsTabs.Items.Cast<System.Windows.Controls.TabItem>().All(t => t.Visibility == Visibility.Visible), "inner settings tabs remain visible under hidden outer TabItem style");
                    var tabBitmap = new RenderTargetBitmap(720, 950, 96, 96, PixelFormats.Pbgra32); tabBitmap.Render(border);
                    var tabEncoder = new PngBitmapEncoder(); tabEncoder.Frames.Add(BitmapFrame.Create(tabBitmap));
                    using var tabFile = File.Create(Path.Combine(AppContext.BaseDirectory, $"remote-settings-{tabIndex}.png")); tabEncoder.Save(tabFile);
                }
                border.Child = null;
            }
        }
        foreach (var file in Directory.GetFiles(settingsDirectory)) File.Delete(file);
        Directory.Delete(settingsDirectory);
        owner.Close(); app.Shutdown();
    }

    private static void UtilityDwell()
    {
        using var relay = new RemoteRelay(false, _ => throw new Exception("utility dwell must not move the pointer"), _ => 11);
        var config = new RelayConfiguration(null, new RemoteSettings { DwellMs = 250 },
            [new(RemoteAction.Settings, new(-1000000, -1000000, 2000000, 2000000), 11)], default, default, false, 1);
        relay.Configure(config);
        Call(relay, "Tick");
        Check(relay.TakeUtility() is null, "utility waits for dwell threshold");
        Thread.Sleep(280);
        Call(relay, "Tick");
        Check(relay.TakeUtility() == RemoteAction.Settings, "actual relay Tick executes settings dwell while phone input is paused");
        Call(relay, "Tick");
        Check(relay.TakeUtility() is null, "utility dwell remains single shot while hovered");
    }

    private const BindingFlags PrivateInstance = BindingFlags.Instance | BindingFlags.NonPublic;
    private static IEnumerable<System.Windows.Controls.TextBox> NumberInputs(System.Windows.Controls.Panel panel) => panel.Children.OfType<System.Windows.Controls.Grid>().SelectMany(g => g.Children.OfType<System.Windows.Controls.StackPanel>()).SelectMany(p => p.Children.OfType<System.Windows.Controls.TextBox>());
    private static void Set(object owner, string field, object? value) => owner.GetType().GetField(field, PrivateInstance)!.SetValue(owner, value);
    private static T Get<T>(object owner, string field) => (T)owner.GetType().GetField(field, PrivateInstance)!.GetValue(owner)!;
    private static object? Call(object owner, string method, params object?[] args) => owner.GetType().GetMethod(method, PrivateInstance)!.Invoke(owner, args);

    private static void RelayCancellation()
    {
        var returned = new List<RemoteNative.Point>();
        nint coveringWindow = 11;
        using var relay = new RemoteRelay(false, returned.Add, _ => coveringWindow);
        var settings = new RemoteSettings { Activation = "click" };
        var config = new RelayConfiguration(null, settings, [new(RemoteAction.Up, new(10, 10, 72, 72), 11)], default, default, false, 1);
        relay.Configure(config); Set(relay, "_revision", 1L);
        Set(relay, "_logical", new RemoteNative.Point(30, 40));
        foreach (var phase in new[] { 1, 2 })
        {
            Set(relay, "_logical", new RemoteNative.Point(30, 40));
            Set(relay, "_phase", phase); Set(relay, "_relaying", true);
            coveringWindow = 11;
            Check(Call(relay, "Hit", config) is RemoteHit, "logical hover stays on visible button during relay");
            coveringWindow = 99;
            Check(Call(relay, "Hit", config) is null, "popup covering logical button cancels hover during relay");
            Set(relay, "_logical", new RemoteNative.Point(40 + phase, 50 + phase));
            Set(relay, "_active", RemoteAction.Up); Set(relay, "_running", config); Set(relay, "_click", RemoteAction.Down);
            Set(relay, "_leftOwned", true); Set(relay, "_held", true); Set(relay, "_pressed", RemoteAction.Up);
            // The actual Tick -> Cancel -> Restore path, without global hooks or SendInput.
            Call(relay, "Tick");
            Check(returned.Count == phase && returned[^1].X == 40 + phase && returned[^1].Y == 50 + phase, "cancel returns to latest logical point");
            Check(Get<int>(relay, "_phase") == 0 && !Get<bool>(relay, "_relaying"), "cancel ends arrival/recovery phase");
            Check(Get<RemoteAction?>(relay, "_click") is null && Get<RemoteAction?>(relay, "_active") is null && Get<RelayConfiguration?>(relay, "_running") is null, "cancel discards pending action");
            Check(Get<bool>(relay, "_leftOwned"), "cancel retains ownership until physical release");
            coveringWindow = 11;
            var data = Marshal.AllocHGlobal(Marshal.SizeOf<RemoteNative.HookData>());
            try
            {
                Marshal.StructureToPtr(new RemoteNative.HookData { Point = new(40 + phase, 50 + phase), Flags = 1 }, data, false);
                Check((nint)Call(relay, "MouseHook", 0, (nint)RemoteNative.LeftUp, data)! == 1, "release after cancel remains absorbed");
            }
            finally { Marshal.FreeHGlobal(data); }
            Check(!Get<bool>(relay, "_leftOwned") && !Get<bool>(relay, "_held"), "release clears click ownership");
            Call(relay, "Tick");
            Check(returned.Count == phase && Get<RemoteAction?>(relay, "_click") is null, "disabled session cannot replay release action");
        }
        relay.Configure(config with { Enabled = true });
        Set(relay, "_phase", 1); Set(relay, "_relaying", true); Set(relay, "_running", config);
        Set(relay, "_click", RemoteAction.Stop);
        Call(relay, "Tick");
        Check(relay.TakeUtility() == RemoteAction.Stop && Get<long>(relay, "_stoppedRevision") == 1, "stop latches inside worker before UI update");
        Call(relay, "Tick");
        Check(returned.Count == 3 && Get<int>(relay, "_phase") == 0, "stopped revision cannot replay excursion");
    }

    private static void LostTarget(RemoteControls controls)
    {
        var targets = Get<System.Windows.Controls.ComboBox>(controls, "_targets");
        var target = new MirrorTarget(0, 0, 0, "test target", "scrcpy.exe", "", [0xA4]);
        targets.ItemsSource = new[] { target }; targets.SelectedItem = target;
        var buttons = Get<Dictionary<RemoteAction, RemoteButtonWindow>>(controls, "_buttons");
        foreach (var action in Enum.GetValues<RemoteAction>())
        {
            // Native windows are entirely off-screen and never activated. This
            // exercises real WPF Hide/visibility without occupying the user's UI.
            var button = new RemoteButtonWindow(action) { Left = -30000, Top = -30000 };
            buttons.Add(action, button); button.Show();
        }
        Check(buttons.Values.All(b => b.IsVisible), "old control windows initially visible");
        Set(controls, "_visible", true);
        targets.ItemsSource = Array.Empty<MirrorTarget>();
        Check(targets.SelectedItem is null && Get<MirrorTarget?>(controls, "_target") is null, "refresh loses old target selection");
        Check(buttons.Values.All(b => !b.IsVisible) && !Get<bool>(controls, "_visible"), "lost selection hides all seven control windows");
        var config = Get<RelayConfiguration>(Get<RemoteRelay>(controls, "_relay"), "_config");
        Check(!config.Enabled && config.Hits.Length == 0, "lost selection clears enabled input and hit regions");
    }

    private static void RefreshedTargets(RemoteControls controls)
    {
        var targets = Get<System.Windows.Controls.ComboBox>(controls, "_targets");
        var first = new MirrorTarget(10, 20, 30, "phone", "scrcpy.exe", "", [0xA4]);
        controls.ApplyTargets([first]);
        Check(targets.Items.Count == 1 && ReferenceEquals(targets.SelectedItem, first) && targets.Visibility == Visibility.Collapsed && !Get<bool>(controls, "_enabled"), "single mirror is selected automatically without starting output");
        targets.SelectedItem = first; Set(controls, "_calibrated", true);
        var refreshed = first with { Title = "updated phone", Modifiers = [0xA4] };
        controls.ApplyTargets([refreshed]);
        Check(ReferenceEquals(targets.SelectedItem, refreshed) && Get<bool>(controls, "_calibrated"), "refresh preserves selected window and video calibration across new metadata arrays");
        Set(controls, "_enabled", true);
        controls.ApplyTargets([refreshed]);
        Check(Get<bool>(controls, "_enabled"), "unchanged window refresh does not pause dwell controls");
        Set(controls, "_covered", true);
        Call(controls, "UpdateConfiguration", (object)Array.Empty<RemoteHit>());
        var relay = Get<RemoteRelay>(controls, "_relay");
        Check(!Get<RelayConfiguration>(relay, "_config").Enabled && Get<bool>(controls, "_enabled"), "covered mirror disables dispatch without losing requested active state");
        Set(controls, "_covered", false);
        Call(controls, "UpdateConfiguration", (object)Array.Empty<RemoteHit>());
        Check(Get<RelayConfiguration>(relay, "_config").Enabled, "uncovered mirror restores readiness with no stale command queue");
        Call(controls, "Change", (Action)(() => Get<RemoteSettings>(controls, "_settings").Gap = 16));
        Check(Get<bool>(controls, "_enabled"), "layout edits resume previously active dwell after cancellation boundary");
        controls.Pause();
        Call(controls, "Change", (Action)(() => Get<RemoteSettings>(controls, "_settings").Gap = 12));
        Check(!Get<bool>(controls, "_enabled"), "editing settings never resumes an explicitly paused session");
        var savedPoint = new RemoteSettings { TargetHint = "phone", CalibratedAspect = .5 };
        Check(RemoteControls.CanReuseScrollPoint(savedPoint, first, new(0, 0, 400, 800)), "saved point matches phone and aspect");
        Check(!RemoteControls.CanReuseScrollPoint(savedPoint, first with { Title = "other phone" }, new(0, 0, 400, 800)), "new phone starts at default center");
        Check(!RemoteControls.CanReuseScrollPoint(savedPoint, first, new(0, 0, 800, 400)), "rotated video needs new scroll point");
        controls.ApplyTargets([first with { Started = 31 }]);
        Check((targets.SelectedItem as MirrorTarget)?.Started == 31 && !Get<bool>(controls, "_calibrated") && !Get<bool>(controls, "_enabled"), "restarted single mirror is reselected with stale calibration and output cleared");
        controls.ApplyTargets([]);
        controls.ApplyTargets([first, first with { Handle = 11, Pid = 21 }]);
        Check(targets.SelectedItem is null && targets.Visibility == Visibility.Visible, "multiple mirrors need a deliberate selection when no current mirror remains");
        targets.SelectedItem = first;
        controls.ApplyTargets([first, first with { Handle = 11, Pid = 21 }]);
        Check(ReferenceEquals(targets.SelectedItem, first), "adding a second mirror does not steal existing selection");
        controls.ApplyTargets([]);
    }

    private static int InventoryUi()
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var owner = new Window();
        var dispatcher = Dispatcher.CurrentDispatcher;
        SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(dispatcher));
        using (var controls = new RemoteControls(owner, AppContext.BaseDirectory, () => { }))
        {
            var refresh = controls.Refresh();
            var frame = new DispatcherFrame();
            _ = refresh.ContinueWith(_ => dispatcher.BeginInvoke(new Action(() => frame.Continue = false)));
            Dispatcher.PushFrame(frame); refresh.GetAwaiter().GetResult();
            var targets = Get<System.Windows.Controls.ComboBox>(controls, "_targets");
            Console.WriteLine($"WPF mirror list count={targets.Items.Count}");
            foreach (MirrorTarget target in targets.Items) Console.WriteLine($"PID={target.Pid} HWND=0x{target.Handle:X} title={target.Title} options={(target.Error.Length == 0 ? "ready" : target.Error)}");
        }
        owner.Close(); app.Shutdown(); return 0;
    }
}
