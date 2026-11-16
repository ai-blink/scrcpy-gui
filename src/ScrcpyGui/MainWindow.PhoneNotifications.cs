using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using Microsoft.Toolkit.Uwp.Notifications;

namespace ScrcpyGui;

/// <summary>
/// Shows phone notifications (from Blink Link's NotifyListener) as Windows toasts.
/// Clicking a toast opens that app alone in a new scrcpy window on a virtual display.
/// </summary>
public partial class MainWindow
{
    private const string NotifySocket = "localabstract:blinklink_notify";
    private const string NotifyListenerComponent = BlinkLinkProvisioner.Package + "/" + BlinkLinkProvisioner.Package + ".NotifyListener";
    private CheckBox? _phoneNotificationsBox;
    private CancellationTokenSource? _notifyCancellation;
    private readonly HashSet<string> _notifyListenerAllowed = new(StringComparer.Ordinal);
    private readonly Dictionary<string, AppWindow> _appWindows = new(StringComparer.Ordinal);
    private string _notifyState = "";
    private StreamWriter? _notifyWriter;
    private string? _notifySerial;

    /// <summary>A scrcpy app window and the virtual display id it reports once started.</summary>
    private sealed record AppWindow(Process Process, TaskCompletionSource<int> Display);

    private void InitializePhoneNotifications()
    {
        if (DeviceBox.Parent is not WrapPanel toolbar) return;
        var box = new CheckBox
        {
            Content = "휴대폰 알림 받기", Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center,
            ToolTip = "휴대폰 알림을 윈도우 알림으로 보여줍니다. 알림을 누르면 그 앱이 새 창으로 열립니다. (Blink Link 0.5.0 이상 필요)",
            IsChecked = _config["phoneNotifications"]?.GetValue<bool>() == true,
        };
        AutomationProperties.SetName(box, "휴대폰 알림을 PC 알림으로 받기");
        box.Checked += (_, _) => SetPhoneNotifications(true);
        box.Unchecked += (_, _) => SetPhoneNotifications(false);
        toolbar.Children.Add(box);
        _phoneNotificationsBox = box;
        if (!_backgroundServices) return;
        // Subscribing registers the toast click handler; a click on a toast from a closed GUI relaunches it here.
        ToastNotificationManagerCompat.OnActivated += activation => Dispatcher.BeginInvoke(() => OnPhoneToastActivated(activation.Argument));
        if (box.IsChecked == true) StartNotificationBridge();
    }

    private void SetPhoneNotifications(bool enabled)
    {
        _config["phoneNotifications"] = enabled;
        SaveObject(ConfigPath, _config);
        if (!_backgroundServices) return;
        if (enabled) StartNotificationBridge();
        else
        {
            _notifyCancellation?.Cancel(); _notifyCancellation = null; _notifyState = "";
            SetStatus("휴대폰 알림 받기를 껐습니다.");
        }
    }

    private void StartNotificationBridge()
    {
        if (_notifyCancellation is not null) return;
        _notifyCancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        _ = RunNotificationBridgeAsync(_notifyCancellation.Token);
    }

    private void ReportNotifyState(string message)
    {
        if (message == _notifyState) return;
        _notifyState = message;
        SetStatus(message);
        if (_phoneNotificationsBox is not null) _phoneNotificationsBox.ToolTip = message;
    }

    private async Task RunNotificationBridgeAsync(CancellationToken token)
    {
        var failures = 0;
        while (!token.IsCancellationRequested)
        {
            string? serial = null; int? port = null; var greeted = false;
            try
            {
                ResolveExecutables();
                serial = EffectiveDeviceId();
                if (_adbPath is null) ReportNotifyState("휴대폰 알림 · adb.exe를 찾지 못했습니다.");
                else if (serial is null) ReportNotifyState("휴대폰 알림 · 연결된 휴대폰을 기다리는 중 (여러 대면 위에서 기기를 고르세요)");
                else
                {
                    if (_notifyListenerAllowed.Add(serial))
                    {
                        // The user opted in with the checkbox; grant notification access for Blink Link only,
                        // plus the overlay app-op Android requires to open a notification's screen from the background.
                        var allowed = await RunProcessAsync(_adbPath, ["-s", serial, "shell", "cmd", "notification", "allow_listener", NotifyListenerComponent], token);
                        await RunProcessAsync(_adbPath, ["-s", serial, "shell", "appops", "set", BlinkLinkProvisioner.Package, "SYSTEM_ALERT_WINDOW", "allow"], token);
                        if (allowed.ExitCode != 0) _notifyListenerAllowed.Remove(serial);
                    }
                    var forward = await RunProcessAsync(_adbPath, ["-s", serial, "forward", "tcp:0", NotifySocket], token);
                    if (forward.ExitCode != 0 || !int.TryParse(forward.Output.Trim(), out var opened)) throw new IOException("adb 포트 연결 실패 · " + forward.Output.Trim());
                    port = opened;
                    using var client = new TcpClient();
                    await client.ConnectAsync(IPAddress.Loopback, opened, token);
                    using var reader = new StreamReader(client.GetStream(), new UTF8Encoding(false));
                    _notifyWriter = new StreamWriter(client.GetStream(), new UTF8Encoding(false)) { AutoFlush = true, NewLine = "\n" };
                    _notifySerial = serial;
                    while (!token.IsCancellationRequested)
                    {
                        using var idle = CancellationTokenSource.CreateLinkedTokenSource(token);
                        idle.CancelAfter(greeted ? TimeSpan.FromSeconds(75) : TimeSpan.FromSeconds(10)); // Blink Link pings every 30 s.
                        string? line;
                        try { line = await reader.ReadLineAsync(idle.Token); }
                        catch (OperationCanceledException) when (!token.IsCancellationRequested) { break; }
                        if (line is null) break;
                        using var json = JsonDocument.Parse(line);
                        var type = json.RootElement.TryGetProperty("type", out var t) ? t.GetString() : null;
                        if (type == "hello")
                        {
                            greeted = true; failures = 0;
                            ReportNotifyState("휴대폰 알림 연결됨 · " + DeviceDisplayName(serial, (_config["devices"] as System.Text.Json.Nodes.JsonObject)?[serial] as System.Text.Json.Nodes.JsonObject));
                        }
                        else if (type == "notification" && greeted) ShowPhoneToast(serial, json.RootElement);
                        else if (type == "opened" && json.RootElement.TryGetProperty("ok", out var ok) && ok.ValueKind == JsonValueKind.False)
                            SetStatus("알림의 해당 화면을 열지 못해 앱 첫 화면으로 열었습니다 · " + Field(json.RootElement, "reason"));
                        if (EffectiveDeviceId() != serial) break; // The user picked another phone.
                    }
                    if (!greeted && !token.IsCancellationRequested)
                        ReportNotifyState("휴대폰 알림 · Blink Link가 응답하지 않습니다. 'Blink Link 설정'으로 0.5.0을 설치하고, 휴대폰 설정의 알림 접근에서 Blink Link를 허용하세요.");
                }
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { }
            catch (Exception ex) when (!token.IsCancellationRequested)
            {
                ReportNotifyState("휴대폰 알림 연결 끊김 · 다시 연결합니다 (" + ex.Message + ")");
            }
            finally
            {
                _notifyWriter = null; _notifySerial = null;
                if (port is int p && serial is not null && _adbPath is not null)
                    await RunProcessAsync(_adbPath, ["-s", serial, "forward", "--remove", "tcp:" + p], CancellationToken.None, TimeSpan.FromSeconds(5));
            }
            if (token.IsCancellationRequested) break;
            failures = greeted ? 0 : Math.Min(failures + 1, 4);
            try { await Task.Delay(TimeSpan.FromSeconds(greeted ? 2 : 5 << failures), token); } catch (OperationCanceledException) { break; }
        }
    }

    private static readonly Regex SafePackage = new(@"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$");

    private static string Field(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";

    private void ShowPhoneToast(string serial, JsonElement root)
    {
        var package = Field(root, "pkg");
        if (!SafePackage.IsMatch(package)) return;
        var app = Field(root, "app"); if (app.Length == 0) app = package;
        var title = Field(root, "title");
        var text = Field(root, "text");
        var builder = new ToastContentBuilder()
            .AddArgument("action", "open").AddArgument("serial", serial).AddArgument("pkg", package).AddArgument("app", app).AddArgument("key", Field(root, "key"))
            .AddText(title.Length > 0 ? title : app);
        if (text.Length > 0) builder.AddText(text);
        builder.AddAttributionText(app);
        if (SaveToastIcon(Field(root, "icon")) is string icon) builder.AddAppLogoOverride(new Uri(icon), ToastGenericAppLogoCrop.Circle);
        // The same phone notification updated again replaces its earlier toast instead of stacking.
        var tag = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(serial + "\n" + Field(root, "key"))))[..32];
        try { builder.Show(toast => { toast.Tag = tag; toast.Group = "phone"; }); }
        catch (Exception ex) { ReportNotifyState("윈도우 알림 표시 실패 · " + ex.Message); }
    }

    private static string? SaveToastIcon(string base64)
    {
        if (base64.Length == 0 || base64.Length > 200_000) return null;
        try
        {
            var bytes = Convert.FromBase64String(base64);
            var directory = Path.Combine(Path.GetTempPath(), "ScrcpyGui-phone-icons");
            Directory.CreateDirectory(directory);
            var path = Path.Combine(directory, Convert.ToHexString(SHA256.HashData(bytes))[..32] + ".png");
            if (!File.Exists(path)) File.WriteAllBytes(path, bytes);
            return path;
        }
        catch (Exception ex) when (ex is FormatException or IOException or UnauthorizedAccessException) { return null; }
    }

    private void OnPhoneToastActivated(string argument)
    {
        ToastArguments args;
        try { args = ToastArguments.Parse(argument); } catch { return; }
        if (!args.TryGetValue("action", out var action) || action != "open") return;
        if (!args.TryGetValue("serial", out var serial) || !args.TryGetValue("pkg", out var package)) return;
        OpenPhoneAppWindow(serial, package, args.TryGetValue("app", out var app) ? app : package, args.TryGetValue("key", out var key) ? key : "");
    }

    /// <summary>Asks Blink Link to run the notification's own action (e.g. that chat) on the app window's display.</summary>
    private async Task OpenNotificationTargetAsync(string serial, string key, AppWindow window, bool fresh)
    {
        if (key.Length == 0) return;
        try
        {
            var display = await window.Display.Task.WaitAsync(TimeSpan.FromSeconds(20), _lifetime.Token);
            // Let scrcpy's --start-app finish first so the notification screen lands on top of it.
            if (fresh) await Task.Delay(1200, _lifetime.Token);
            if (_notifyWriter is null || _notifySerial != serial) { SetStatus("휴대폰 알림 연결이 끊겨 앱 첫 화면으로 열었습니다."); return; }
            await _notifyWriter.WriteLineAsync(JsonSerializer.Serialize(new { type = "open", key, display }));
        }
        catch (Exception ex) when (ex is TimeoutException or IOException or ObjectDisposedException)
        {
            SetStatus("앱 창의 화면 번호를 확인하지 못해 앱 첫 화면으로 열었습니다.");
        }
        catch (OperationCanceledException) { }
    }

    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(nint hwnd, int command);

    /// <summary>One window per app: scrcpy creates a virtual display and starts only that app on it.</summary>
    private void OpenPhoneAppWindow(string serial, string package, string app, string notificationKey)
    {
        if (!SafePackage.IsMatch(package) || serial.Length == 0 || serial.StartsWith('-') || serial.Any(c => char.IsWhiteSpace(c) || char.IsControl(c))) return;
        ResolveExecutables();
        if (_scrcpyPath is null) { SetStatus("scrcpy.exe를 찾지 못해 앱 창을 열지 못했습니다."); return; }
        var key = serial + "|" + package;
        if (_appWindows.TryGetValue(key, out var existing) && !existing.Process.HasExited)
        {
            existing.Process.Refresh();
            var handle = existing.Process.MainWindowHandle;
            if (handle != 0) { ShowWindow(handle, 9 /* SW_RESTORE */); SetForegroundWindow(handle); }
            _ = OpenNotificationTargetAsync(serial, notificationKey, existing, false);
            return;
        }
        var start = new ProcessStartInfo
        {
            FileName = _scrcpyPath, WorkingDirectory = Path.GetDirectoryName(_scrcpyPath)!,
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true,
        };
        // Audio stays with the main mirror; each app window only carries video and input.
        foreach (var argument in new[] { "-s", serial, "--start-app=" + package, "--no-audio", "--window-title=" + app + " · 휴대폰" }.Concat(AppWindowPresetArguments()))
            start.ArgumentList.Add(argument);
        try
        {
            var process = Process.Start(start) ?? throw new InvalidOperationException("프로세스를 시작하지 못했습니다.");
            var window = new AppWindow(process, new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously));
            _appWindows[key] = window;
            SetStatus(app + " 앱을 새 창으로 여는 중…");
            _ = WatchAppWindowAsync(key, app, window);
            _ = OpenNotificationTargetAsync(serial, notificationKey, window, true);
        }
        catch (Exception ex) { SetStatus(app + " 앱 창 실행 실패 · " + ex.Message); }
    }

    // Size, quality, window and input options from the current settings. Power, audio, recording and
    // display/app selection stay out: they belong to the main mirror or would affect the whole phone.
    private static readonly string[] AppWindowOptionKeys =
    [
        "max-size", "max-fps", "video-bit-rate", "video-codec", "always-on-top", "borderless", "window-width", "window-height",
        "render-driver", "keyboard", "mouse", "show-touches", "prefer-text", "no-key-repeat", "no-control",
    ];

    private IEnumerable<string> AppWindowPresetArguments()
    {
        foreach (var key in AppWindowOptionKeys)
        {
            if (!_definitions.TryGetValue(key, out var definition) || string.IsNullOrEmpty(definition.Argument)) continue;
            if (definition.Kind == OptionKind.Check) { if (ReadChecked(key)) yield return definition.Argument; continue; }
            var value = ReadText(key).Trim();
            if (value.Length > 0 && value != DefaultChoice) yield return definition.Argument.Replace("{0}", value, StringComparison.Ordinal);
        }
        // A preset with its own virtual display size (e.g. landscape 1920x1080) sizes the app window too.
        var size = ReadText("new-display").Trim();
        yield return size.Length > 0 && size != DefaultChoice ? "--new-display=" + size : "--new-display";
    }

    private static readonly Regex NewDisplayLine = new(@"New display: .*\(id=(\d+)\)");

    private async Task WatchAppWindowAsync(string key, string app, AppWindow window)
    {
        var process = window.Process;
        var lines = new Queue<string>(); var gate = new object();
        DataReceivedEventHandler receive = (_, e) =>
        {
            if (string.IsNullOrWhiteSpace(e.Data)) return;
            if (NewDisplayLine.Match(e.Data) is { Success: true } m) window.Display.TrySetResult(int.Parse(m.Groups[1].Value));
            lock (gate) { lines.Enqueue(e.Data); while (lines.Count > 6) lines.Dequeue(); }
        };
        process.ErrorDataReceived += receive; process.OutputDataReceived += receive;
        try
        {
            process.BeginErrorReadLine(); process.BeginOutputReadLine();
            await process.WaitForExitAsync(_lifetime.Token);
            if (process.ExitCode != 0)
            {
                string details; lock (gate) details = string.Join("\n", lines);
                SetStatus(app + " 앱 창이 종료됐습니다 (scrcpy 3.0 이상, Android 10 이상 필요). " + details[..Math.Min(details.Length, 600)]);
            }
        }
        catch (OperationCanceledException) { /* Closing the GUI leaves app windows open, like the main mirror. */ }
        finally
        {
            window.Display.TrySetCanceled();
            if (_appWindows.TryGetValue(key, out var current) && ReferenceEquals(current, window)) _appWindows.Remove(key);
            process.Dispose();
        }
    }
}
