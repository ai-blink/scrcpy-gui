using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;

namespace ScrcpyGui;

public partial class MainWindow
{
    private Window? _blinkSetupWindow;

    private void InitializeBlinkLinkSetup()
    {
        // Extend the existing wrapping toolbar without changing the user's XAML edits.
        if (DeviceBox.Parent is not WrapPanel toolbar) return;
        var button = new Button { Content = "Blink Link 설정", ToolTip = "선택한 휴대폰에 Blink Link를 설치하고 최초 권한을 설정합니다.", Margin = new Thickness(8, 0, 0, 0) };
        AutomationProperties.SetName(button, "Blink Link 설치와 최초 권한 설정");
        button.Click += (_, _) => OpenBlinkLinkSetup();
        toolbar.Children.Add(button);
    }

    private void OpenBlinkLinkSetup()
    {
        if (_blinkSetupWindow is not null) { _blinkSetupWindow.Activate(); return; }
        ResolveExecutables();
        if (_adbPath is null) { SetStatus("adb.exe를 찾지 못했습니다. 설정 화면에서 실행 파일 위치를 지정하세요."); return; }
        var adbPath = _adbPath;
        var dialog = CreateDarkDialog("Blink Link 준비", 600, 640);
        dialog.MinWidth = Math.Min(420, SystemParameters.WorkArea.Width - 24); dialog.MinHeight = Math.Min(420, SystemParameters.WorkArea.Height - 24);
        dialog.MaxHeight = SystemParameters.WorkArea.Height;
        dialog.Width = Math.Min(dialog.Width, SystemParameters.WorkArea.Width - 24);
        dialog.Height = Math.Min(dialog.Height, SystemParameters.WorkArea.Height - 24);
        _blinkSetupWindow = dialog;
        using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        var token = cancellation.Token;
        var body = new StackPanel { Margin = new Thickness(24) };
        TextBlock Text(string value, int size = 15) { var t = new TextBlock { Text = value, FontSize = size, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 14) }; body.Children.Add(t); return t; }
        Text("명령어 없이 휴대폰을 준비하세요", 23);
        Text("연결된 휴대폰을 고르면 Blink Link 0.3.2 설치와 연결 복구에 필요한 최초 권한 설정을 함께 처리합니다. 기존 앱 데이터는 유지합니다.");
        Text("설정할 휴대폰", 17);
        var devices = new ComboBox { MinHeight = 48, FontSize = 16, Margin = new Thickness(0, 0, 0, 14) };
        AutomationProperties.SetName(devices, "Blink Link를 설정할 휴대폰");
        body.Children.Add(devices);
        var refresh = new Button { Content = "연결된 휴대폰 새로고침", MinHeight = 48, HorizontalAlignment = HorizontalAlignment.Stretch };
        body.Children.Add(refresh);
        Text("처음 연결이라면 PC 앱 상단의 페어링을 먼저 진행하세요. 휴대폰에 연결 허용 창이 나타나면 직접 허용해야 합니다.");
        Text("이 버튼은 선택한 휴대폰에서 Blink Link가 무선 디버깅을 켜도록 요청할 수 있게 합니다. 다른 휴대폰의 설정은 바꾸지 않습니다.");
        var install = new Button { Content = "이 휴대폰에 설치 · 권한 설정", MinHeight = 56, FontSize = 18, Background = (Brush)FindResource("Accent"), Foreground = Brushes.Black, Margin = new Thickness(0, 8, 0, 14), IsEnabled = false };
        body.Children.Add(install);
        var status = Text("연결된 휴대폰을 확인하고 있습니다…");
        AutomationProperties.SetLiveSetting(status, AutomationLiveSetting.Polite);
        var close = new Button { Content = "닫기", MinHeight = 48 }; body.Children.Add(close);
        close.Click += (_, _) => dialog.Close();
        // Keep the action and outcome visible while the instructions scroll.
        var footer = new StackPanel { Margin = new Thickness(24, 12, 24, 16) };
        foreach (var item in new FrameworkElement[] { install, status, close }) { body.Children.Remove(item); footer.Children.Add(item); }
        close.HorizontalAlignment = HorizontalAlignment.Right; close.MinWidth = 100;
        var layout = new Grid(); layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.Children.Add(new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
        var footerBorder = new Border { Child = footer, BorderBrush = (Brush)FindResource("Line"), BorderThickness = new Thickness(0, 1, 0, 0) };Grid.SetRow(footerBorder, 1);layout.Children.Add(footerBorder);dialog.Content = layout;
        bool busy = false;
        async Task LoadDevices()
        {
            refresh.IsEnabled = install.IsEnabled = false;
            try
            {
                var result = await RunProcessAsync(adbPath, ["devices", "-l"], token);
                token.ThrowIfCancellationRequested();
                if (result.ExitCode != 0) throw new InvalidOperationException(result.Output);
                var choices = result.Output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
                    .Select(line => System.Text.RegularExpressions.Regex.Match(line, @"^(\S+)\s+device\b(?:.*?\bmodel:(\S+))?"))
                    .Where(m => m.Success)
                    .Select(m => new DeviceChoice(m.Groups[1].Value, DeviceDisplayName(m.Groups[1].Value, (_config["devices"] as System.Text.Json.Nodes.JsonObject)?[m.Groups[1].Value] as System.Text.Json.Nodes.JsonObject) + " · " + m.Groups[1].Value, false)).ToArray();
                devices.ItemsSource = choices;
                devices.SelectedItem = choices.FirstOrDefault(d => d.Id == EffectiveDeviceId()) ?? (choices.Length == 1 ? choices[0] : null);
                status.Text = choices.Length == 0 ? "연결된 휴대폰이 없습니다. 창을 닫고 페어링 또는 기기 찾기를 진행한 뒤 다시 열어주세요." : "목록에서 대상 휴대폰을 확인하고 설치 버튼을 누르세요.";
                install.IsEnabled = devices.SelectedItem is DeviceChoice;
            }
            catch (OperationCanceledException) { }
            catch (Exception ex) { status.Text = "기기 확인 실패 · " + ex.Message; }
            finally { refresh.IsEnabled = true; }
        }
        devices.SelectionChanged += (_, _) => { if (!busy) install.IsEnabled = devices.SelectedItem is DeviceChoice; };
        refresh.Click += async (_, _) => await LoadDevices();
        install.Click += async (_, _) =>
        {
            if (busy || devices.SelectedItem is not DeviceChoice { Id: not null } target) return;
            busy = true; devices.IsEnabled = refresh.IsEnabled = install.IsEnabled = false; close.Content = "취소하고 닫기";
            string? directory = null;
            try
            {
                directory = Path.Combine(Path.GetTempPath(), "ScrcpyGui-BlinkLink-" + Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
                var apk = Path.Combine(directory, "BlinkLink-0.3.2.apk");
                using (var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("BlinkLink.apk") ?? throw new InvalidOperationException("설치 파일이 포함되지 않은 실행 파일입니다. 새 배포본을 받아주세요."))
                using (var file = File.Create(apk)) await resource.CopyToAsync(file, token);
                var setup = new BlinkLinkProvisioner(async (args, token, timeout) => { var reply = await RunProcessAsync(adbPath, args, token, timeout);return new BlinkAdbResult(reply.ExitCode, reply.Output); });
                await setup.PrepareAsync(target.Id, apk, new Progress<string>(s => status.Text = s + "…"), token);
                status.Text = "설치와 최초 권한 설정을 확인했습니다. 휴대폰에서 Blink Link를 열었습니다. 앱의 설정에서 위치·알림 권한을 허용하고 사용할 Wi-Fi를 등록하세요.";
                SetStatus("Blink Link 준비 완료 · " + target.Label);
            }
            catch (OperationCanceledException) { SetStatus("Blink Link 준비를 취소했습니다. 이미 설치된 앱이나 적용된 권한은 유지됩니다."); }
            catch (Exception ex) { status.Text = ex.Message;SetStatus("Blink Link 준비 실패 · " + ex.Message); }
            finally
            {
                busy = false;devices.IsEnabled = refresh.IsEnabled = true;install.IsEnabled = devices.SelectedItem is DeviceChoice;close.Content = "닫기";
                if (directory is not null) { try { File.Delete(Path.Combine(directory, "BlinkLink-0.3.2.apk"));Directory.Delete(directory); } catch { /* Temporary APK only; never remove other files. */ } }
            }
        };
        dialog.Loaded += async (_, _) => await LoadDevices();
        dialog.Closing += (_, _) => cancellation.Cancel();
        try { dialog.ShowDialog(); } finally { _blinkSetupWindow = null; }
    }
}
