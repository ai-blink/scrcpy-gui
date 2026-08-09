using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace ScrcpyGui;

public partial class MainWindow : Window
{
    private const string DefaultChoice = "(기본)";
    private readonly Dictionary<string, OptionDefinition> _definitions;
    private readonly Dictionary<string, FrameworkElement> _controls = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _deviceIds = new(StringComparer.Ordinal);
    private readonly string _dataDirectory;
    private JsonObject _config;
    private JsonObject _presets;
    private bool _updating;
    private string? _scrcpyPath;
    private string? _adbPath;

    public MainWindow()
    {
        InitializeComponent();
        FitToWorkArea();
        _dataDirectory = ResolveDataDirectory();
        _definitions = Definitions().ToDictionary(item => item.Key, StringComparer.Ordinal);
        _config = LoadObject(ConfigPath);
        _presets = LoadObject(PresetPath);
        if (_presets.Count == 0)
        {
            _presets = DefaultPresets();
            SaveObject(PresetPath, _presets);
        }

        BuildOptionTabs();
        RestoreLastValues();
        ReloadPresetList();
        ResolveExecutables();
        NavigationList.SelectedIndex = 0;
        OptionTabs.SelectedIndex = 0;
        UpdatePreview();
        Loaded += async (_, _) =>
        {
            await RefreshDevicesAsync();
            await SyncPhonePreferencesAsync();
        };
    }

    private string ConfigPath => Path.Combine(_dataDirectory, "scrcpy-gui-config.json");
    private string PresetPath => Path.Combine(_dataDirectory, "scrcpy-gui-presets.json");
    private string LastPath => Path.Combine(_dataDirectory, "scrcpy-gui-last.json");

    private static string ResolveDataDirectory()
    {
        var current = Environment.CurrentDirectory;
        if (File.Exists(Path.Combine(current, "scrcpy-gui.ps1")) ||
            File.Exists(Path.Combine(current, "scrcpy-gui-config.json")))
        {
            return current;
        }

        var parent = Directory.GetParent(AppContext.BaseDirectory)?.FullName;
        if (parent is not null && File.Exists(Path.Combine(parent, "scrcpy-gui.ps1")))
        {
            return parent;
        }

        return AppContext.BaseDirectory;
    }

    private void FitToWorkArea()
    {
        var workArea = SystemParameters.WorkArea;
        MinWidth = Math.Min(MinWidth, Math.Max(720, workArea.Width - 24));
        MinHeight = Math.Min(MinHeight, Math.Max(560, workArea.Height - 24));
        Width = Math.Max(MinWidth, Math.Min(Width, workArea.Width - 24));
        Height = Math.Max(MinHeight, Math.Min(Height, workArea.Height - 24));
    }

    private void BuildOptionTabs()
    {
        foreach (var group in Definitions().GroupBy(item => item.Group))
        {
            var form = new StackPanel { Margin = new Thickness(18) };
            foreach (var definition in group)
            {
                var row = new Grid { Margin = new Thickness(0, 0, 0, 14) };
                row.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                row.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                var label = new TextBlock
                {
                    Text = definition.Label,
                    VerticalAlignment = VerticalAlignment.Center,
                    Foreground = System.Windows.Media.Brushes.Gainsboro,
                    TextWrapping = TextWrapping.Wrap,
                };
                Grid.SetColumn(label, 0);
                row.Children.Add(label);

                var control = CreateControl(definition);
                control.HorizontalAlignment = HorizontalAlignment.Left;
                control.Width = 280;
                Grid.SetColumn(control, 1);
                row.Children.Add(control);

                var hint = new TextBlock
                {
                    Text = definition.Hint,
                    Margin = new Thickness(0, 5, 0, 0),
                    VerticalAlignment = VerticalAlignment.Center,
                    Foreground = System.Windows.Media.Brushes.LightSteelBlue,
                    HorizontalAlignment = HorizontalAlignment.Left,
                    LineHeight = 18,
                    Width = 280,
                    TextWrapping = TextWrapping.Wrap,
                };
                Grid.SetRow(hint, 1);
                Grid.SetColumn(hint, 1);
                row.Children.Add(hint);
                form.Children.Add(row);
            }

            var card = new Border
            {
                Background = (System.Windows.Media.Brush)FindResource("Surface"),
                BorderBrush = (System.Windows.Media.Brush)FindResource("Line"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(12),
                Child = form,
            };
            var header = new Border
            {
                Background = (System.Windows.Media.Brush)FindResource("SurfaceRaised"),
                BorderBrush = (System.Windows.Media.Brush)FindResource("Line"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(12),
                Padding = new Thickness(16),
                Margin = new Thickness(0, 0, 0, 16),
            };
            var headerContent = new Grid();
            headerContent.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) });
            headerContent.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            headerContent.Children.Add(new TextBlock
            {
                Text = group.Key,
                FontSize = 20,
                FontWeight = FontWeights.SemiBold,
                Foreground = (System.Windows.Media.Brush)FindResource("Text"),
                VerticalAlignment = VerticalAlignment.Center,
            });
            var description = new TextBlock
            {
                Text = "미러링 세션에 적용할 옵션을 선택하세요.",
                Foreground = (System.Windows.Media.Brush)FindResource("Faint"),
                Margin = new Thickness(16, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
                TextWrapping = TextWrapping.Wrap,
            };
            Grid.SetColumn(description, 1);
            headerContent.Children.Add(description);
            header.Child = headerContent;

            var page = new StackPanel { Margin = new Thickness(4, 0, 4, 20) };
            page.Children.Add(header);
            page.Children.Add(card);
            var scroll = new ScrollViewer
            {
                Content = page,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            };
            void FitPageToViewport()
            {
                if (scroll.ViewportWidth > page.Margin.Left + page.Margin.Right)
                {
                    page.Width = scroll.ViewportWidth - page.Margin.Left - page.Margin.Right;
                }
            }
            scroll.Loaded += (_, _) => FitPageToViewport();
            scroll.SizeChanged += (_, _) => FitPageToViewport();
            OptionTabs.Items.Add(new TabItem { Header = group.Key, Content = scroll });
        }
    }

    private void NavigationList_OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_updating || NavigationList.SelectedItem is not ListBoxItem item || item.Tag is not string group) return;
        var index = OptionTabs.Items.Cast<TabItem>().ToList().FindIndex(tab => Equals(tab.Header, group));
        if (index >= 0) OptionTabs.SelectedIndex = index;
    }

    private void OptionTabs_OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_updating || e.Source != OptionTabs || OptionTabs.SelectedItem is not TabItem tab) return;
        foreach (var item in NavigationList.Items.OfType<ListBoxItem>())
        {
            if (Equals(item.Tag, tab.Header))
            {
                NavigationList.SelectedItem = item;
                break;
            }
        }
    }

    private FrameworkElement CreateControl(OptionDefinition definition)
    {
        FrameworkElement control;
        switch (definition.Kind)
        {
            case OptionKind.Check:
            case OptionKind.PhonePreference:
            {
                var box = new CheckBox
                {
                    IsChecked = definition.DefaultChecked,
                    VerticalAlignment = VerticalAlignment.Center,
                    ToolTip = definition.Hint,
                };
                box.Checked += definition.Kind == OptionKind.PhonePreference ? PhonePreferenceChanged : AnyOptionChanged;
                box.Unchecked += definition.Kind == OptionKind.PhonePreference ? PhonePreferenceChanged : AnyOptionChanged;
                control = box;
                break;
            }
            case OptionKind.Combo:
            case OptionKind.EditableCombo:
            {
                var combo = new ComboBox
                {
                    Height = 34,
                    IsEditable = definition.Kind == OptionKind.EditableCombo,
                    ToolTip = definition.Hint,
                };
                foreach (var item in definition.Items ?? []) combo.Items.Add(item);
                combo.Text = definition.DefaultText;
                combo.SelectionChanged += AnyOptionChanged;
                combo.LostFocus += AnyOptionChanged;
                control = combo;
                break;
            }
            case OptionKind.Path:
            {
                var panel = new Grid();
                panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                panel.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var path = new TextBox
                {
                    Height = 34,
                    ToolTip = definition.Hint,
                    Text = ReadString(_config[definition.Key]),
                };
                path.TextChanged += (_, _) =>
                {
                    if (!_updating) SaveConfiguredPaths();
                };
                var browse = new Button { Content = "찾아보기", Margin = new Thickness(8, 0, 0, 0) };
                browse.Click += (_, _) => BrowseForExecutable(definition, path);
                panel.Children.Add(path);
                Grid.SetColumn(browse, 1);
                panel.Children.Add(browse);
                control = panel;
                _controls[definition.Key] = path;
                return control;
            }
            default:
            {
                var text = new TextBox { Height = 34, Text = definition.DefaultText, ToolTip = definition.Hint };
                text.TextChanged += AnyOptionChanged;
                control = text;
                break;
            }
        }

        _controls[definition.Key] = control;
        return control;
    }

    private void BrowseForExecutable(OptionDefinition definition, TextBox target)
    {
        var dialog = new OpenFileDialog
        {
            Filter = definition.Key == "adbPath" ? "adb.exe|adb.exe" : "scrcpy.exe|scrcpy.exe",
            CheckFileExists = true,
            Multiselect = false,
        };
        if (dialog.ShowDialog(this) != true) return;
        target.Text = dialog.FileName;
        ResolveExecutables();
        UpdatePreview();
    }

    private void SaveConfiguredPaths()
    {
        _config["scrcpyPath"] = ReadText("scrcpyPath");
        _config["adbPath"] = ReadText("adbPath");
        SaveObject(ConfigPath, _config);
        ResolveExecutables();
        UpdatePreview();
    }

    private void ResolveExecutables()
    {
        _scrcpyPath = HighestVersionPath(
            new string?[] { ReadText("scrcpyPath"), Path.Combine(_dataDirectory, "scrcpy.exe") }
                .Concat(FindMatchingFiles(@"C:\app", "scrcpy*", "scrcpy.exe")));

        _adbPath = FirstExisting(
            ReadText("adbPath"),
            _scrcpyPath is null ? null : Path.Combine(Path.GetDirectoryName(_scrcpyPath)!, "adb.exe"),
            Path.Combine(_dataDirectory, "adb.exe"),
            @"C:\app\adb\adb.exe",
            @"C:\app\scrcpy-win64-v4.1\adb.exe");

        _updating = true;
        try
        {
            if (_controls.TryGetValue("scrcpyPath", out var scrcpy)) ((TextBox)scrcpy).Text = _scrcpyPath ?? ReadText("scrcpyPath");
            if (_controls.TryGetValue("adbPath", out var adb)) ((TextBox)adb).Text = _adbPath ?? ReadText("adbPath");
        }
        finally { _updating = false; }
    }

    private static IEnumerable<string> FindMatchingFiles(string root, string directoryPattern, string fileName)
    {
        if (!Directory.Exists(root)) return [];
        try
        {
            return Directory.EnumerateDirectories(root, directoryPattern)
                .Select(directory => Path.Combine(directory, fileName))
                .Where(File.Exists)
                .ToArray();
        }
        catch { return []; }
    }

    private static string? FirstExisting(params string?[] candidates) => candidates.FirstOrDefault(path => !string.IsNullOrWhiteSpace(path) && File.Exists(path));

    private static string? HighestVersionPath(IEnumerable<string?> candidates) => candidates
        .Where(path => !string.IsNullOrWhiteSpace(path) && File.Exists(path))
        .OrderByDescending(path => ExtractVersion(path!))
        .FirstOrDefault();

    private static Version ExtractVersion(string path)
    {
        var match = Regex.Match(path, @"(?:v|win64-)(?<version>\d+(?:\.\d+){1,3})", RegexOptions.IgnoreCase);
        return match.Success && Version.TryParse(match.Groups["version"].Value, out var version) ? version : new Version(0, 0);
    }

    private async void RefreshButton_OnClick(object sender, RoutedEventArgs e) => await RefreshDevicesAsync();

    private async Task RefreshDevicesAsync()
    {
        if (!EnsureAdb(showMessage: false))
        {
            SetStatus("adb.exe를 찾지 못했습니다 — 설정 탭에서 위치를 지정하세요.");
            return;
        }

        RefreshButton.IsEnabled = false;
        try
        {
            SetStatus("연결된 기기 확인 중…");
            var devices = await GetAdbDevicesAsync();
            PopulateDevices(devices);
        }
        finally { RefreshButton.IsEnabled = true; }
    }

    private async void DiscoverButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdb()) return;
        DiscoverButton.IsEnabled = false;
        RefreshButton.IsEnabled = false;
        try
        {
            SetStatus("기기 찾는 중 — 폰이 스스로 붙기를 기다립니다…");
            if (await WaitForDeviceAsync(5))
            {
                await RefreshDevicesAsync();
                SetStatus("연결됐습니다 — 실행을 누르세요.");
                return;
            }

            var restart = MessageBox.Show(
                "ADB를 다시 시작해 무선 탐색을 복구합니다.\n열려 있는 scrcpy 미러링 창이 끊길 수 있습니다.\n\n계속할까요?",
                "기기 찾기", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (restart != MessageBoxResult.Yes)
            {
                SetStatus("기기 찾기를 중단했습니다.");
                return;
            }

            SetStatus("ADB를 다시 시작합니다 — 열려 있는 미러링 창이 끊길 수 있습니다…");
            await RunAdbAsync(["kill-server"]);
            if (await WaitForDeviceAsync(18))
            {
                await RefreshDevicesAsync();
                SetStatus("연결됐습니다 — 실행을 누르세요.");
                return;
            }

            SetStatus("같은 Wi-Fi에서 폰을 검색합니다…");
            var mdns = await RunAdbAsync(["mdns", "services"]);
            var endpoints = Regex.Matches(mdns.Output, @"(?<ip>\d{1,3}(?:\.\d{1,3}){3}):(?<port>\d{1,5})")
                .Select(match => match.Value)
                .Distinct(StringComparer.Ordinal)
                .ToArray();
            foreach (var endpoint in endpoints)
            {
                var parts = endpoint.Split(':');
                if (parts.Length != 2 || !int.TryParse(parts[1], out var port) || !await TcpOpenAsync(parts[0], port)) continue;
                SetStatus($"기기 찾는 중 — {endpoint}에 연결합니다…");
                await RunAdbAsync(["connect", endpoint]);
            }

            await RefreshDevicesAsync();
            if (!HasOnlineDevice())
            {
                SetStatus("폰을 찾지 못했습니다 — 폰에서 무선 디버깅을 켜고 같은 Wi-Fi인지 확인하세요.");
            }
        }
        finally
        {
            DiscoverButton.IsEnabled = true;
            RefreshButton.IsEnabled = true;
        }
    }

    private async Task<bool> WaitForDeviceAsync(int seconds)
    {
        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        do
        {
            var devices = await GetAdbDevicesAsync();
            if (devices.Any(device => device.State == "device"))
            {
                PopulateDevices(devices);
                return true;
            }
            await Task.Delay(700);
        } while (DateTime.UtcNow < deadline);

        return false;
    }

    private async Task<List<DeviceInfo>> GetAdbDevicesAsync()
    {
        var result = await RunAdbAsync(["devices", "-l"]);
        var devices = new List<DeviceInfo>();
        foreach (var line in result.Output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            var match = Regex.Match(line, @"^(?<id>\S+)\s+(?<state>device|offline|unauthorized|authorizing|connecting|recovery|sideload|bootloader)\b");
            if (!match.Success) continue;
            var model = Regex.Match(line, @"\smodel:(?<model>\S+)");
            devices.Add(new DeviceInfo(match.Groups["id"].Value, match.Groups["state"].Value, model.Success ? model.Groups["model"].Value : ""));
        }
        return devices;
    }

    private void PopulateDevices(IReadOnlyCollection<DeviceInfo> devices)
    {
        var selected = DeviceBox.SelectedItem as string;
        var online = devices.Where(device => device.State == "device").ToArray();
        var known = _config["devices"] as JsonObject ?? new JsonObject();
        foreach (var device in online)
        {
            known[device.Id] = new JsonObject { ["model"] = device.Model, ["lastSeen"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm") };
        }
        if (online.Length > 0)
        {
            _config["devices"] = known;
            SaveObject(ConfigPath, _config);
        }

        _updating = true;
        try
        {
            _deviceIds.Clear();
            DeviceBox.Items.Clear();
            DeviceBox.Items.Add("(자동)");
            foreach (var device in online)
            {
                var label = string.IsNullOrWhiteSpace(device.Model) ? device.Id : $"{device.Model}  ·  {device.Id}";
                _deviceIds[label] = device.Id;
                DeviceBox.Items.Add(label);
            }
            foreach (var property in known.OrderBy(item => item.Key, StringComparer.Ordinal))
            {
                if (online.Any(device => device.Id == property.Key)) continue;
                var model = property.Value?["model"]?.GetValue<string>() ?? "";
                var label = string.IsNullOrWhiteSpace(model) ? $"(오프라인) {property.Key}" : $"(오프라인) {model}  ·  {property.Key}";
                _deviceIds[label] = property.Key;
                DeviceBox.Items.Add(label);
            }
            DeviceBox.SelectedItem = selected is not null && DeviceBox.Items.Contains(selected) ? selected : "(자동)";
        }
        finally { _updating = false; }

        if (_scrcpyPath is null) SetStatus("scrcpy.exe를 찾지 못했습니다 — 설정 탭에서 위치를 지정하세요.");
        else if (online.Length > 0) SetStatus($"기기 {online.Length}대 연결됨");
        else if (devices.Any(device => device.State == "unauthorized")) SetStatus("무선 디버깅 허용 대기 — 폰에서 허용한 뒤 새로고침하세요.");
        else SetStatus("연결된 기기 없음 — 기기 찾기를 눌러보세요.");
        UpdatePreview();
    }

    private bool HasOnlineDevice() => _deviceIds.Keys.Any(label => !label.StartsWith("(오프라인)", StringComparison.Ordinal) && label != "(자동)");

    private async void PairButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdb()) return;
        var endpoint = new TextBox { Height = 34, ToolTip = "예: 192.168.0.5:41234" };
        var code = new PasswordBox { Height = 34 };
        var pair = new Button { Content = "페어링", IsDefault = true, Padding = new Thickness(14, 7, 14, 7) };
        var dialog = new Window
        {
            Owner = this,
            Title = "무선 페어링",
            Width = 470,
            SizeToContent = SizeToContent.Height,
            ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = System.Windows.Media.Brushes.WhiteSmoke,
        };
        var panel = new StackPanel { Margin = new Thickness(24) };
        panel.Children.Add(new TextBlock { Text = "폰에서 ‘페어링 코드로 기기 페어링’을 연 뒤 값을 입력하세요.", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 18) });
        panel.Children.Add(new TextBlock { Text = "IP:포트", Margin = new Thickness(0, 0, 0, 5) });
        panel.Children.Add(endpoint);
        panel.Children.Add(new TextBlock { Text = "6자리 페어링 코드", Margin = new Thickness(0, 14, 0, 5) });
        panel.Children.Add(code);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 22, 0, 0) };
        var cancel = new Button { Content = "취소", IsCancel = true, Padding = new Thickness(14, 7, 14, 7) };
        cancel.Click += (_, _) => dialog.Close();
        pair.Click += async (_, _) =>
        {
            if (!Regex.IsMatch(endpoint.Text.Trim(), @"^(?:\d{1,3}\.){3}\d{1,3}:\d{1,5}$"))
            {
                MessageBox.Show(dialog, "폰에 표시된 IPv4 주소와 포트를 입력하세요.", "무선 페어링", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            if (!Regex.IsMatch(code.Password.Trim(), @"^\d{6}$"))
            {
                MessageBox.Show(dialog, "폰에 표시된 6자리 페어링 코드를 입력하세요.", "무선 페어링", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            pair.IsEnabled = false;
            var result = await RunAdbAsync(["pair", endpoint.Text.Trim(), code.Password.Trim()]);
            pair.IsEnabled = true;
            if (result.ExitCode == 0 && !Regex.IsMatch(result.Output, "cannot|failed|refused", RegexOptions.IgnoreCase))
            {
                dialog.Close();
                await RefreshDevicesAsync();
                MessageBox.Show(this, "페어링했습니다. 목록에 기기가 보이면 실행을 누르세요.", "무선 페어링", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            else
            {
                MessageBox.Show(dialog, $"페어링에 실패했습니다.\n\n{(string.IsNullOrWhiteSpace(result.Output) ? "adb pair 명령이 실패했습니다." : result.Output)}", "무선 페어링", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        };
        actions.Children.Add(cancel);
        actions.Children.Add(pair);
        panel.Children.Add(actions);
        dialog.Content = panel;
        dialog.ShowDialog();
    }

    private async Task SyncPhonePreferencesAsync()
    {
        if (!EnsureAdb(showMessage: false)) return;
        foreach (var definition in _definitions.Values.Where(item => item.Kind == OptionKind.PhonePreference))
        {
            var result = await RunAdbAsync(["shell", "settings", "get", definition.SettingNamespace!, definition.SettingKey!]);
            if (_controls[definition.Key] is not CheckBox box) continue;
            _updating = true;
            try { box.IsChecked = result.Output.Trim() == "1"; }
            finally { _updating = false; }
        }
    }

    private async void PhonePreferenceChanged(object sender, RoutedEventArgs e)
    {
        if (_updating || sender is not CheckBox box) return;
        var definition = _definitions.Values.FirstOrDefault(item => ReferenceEquals(_controls[item.Key], box));
        if (definition is null || !EnsureAdb(showMessage: false))
        {
            await SyncPhonePreferencesAsync();
            return;
        }

        var desired = box.IsChecked == true ? "1" : "0";
        var result = MessageBox.Show(
            $"‘{definition.Label}’ 설정을 폰에 즉시 {(desired == "1" ? "켭니다" : "끕니다")}.\n되돌리려면 이 토글을 반대로 바꾸면 됩니다.\n\n계속할까요?",
            "폰 설정 변경", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (result != MessageBoxResult.Yes)
        {
            await SyncPhonePreferencesAsync();
            return;
        }

        var command = await RunAdbAsync(["shell", "settings", "put", definition.SettingNamespace!, definition.SettingKey!, desired]);
        if (command.ExitCode != 0)
        {
            MessageBox.Show(this, "폰 설정을 바꾸지 못했습니다. 기기 연결 상태를 확인하세요.", "폰 설정 변경", MessageBoxButton.OK, MessageBoxImage.Error);
            await SyncPhonePreferencesAsync();
        }
    }

    private void AnyOptionChanged(object? sender, EventArgs e)
    {
        if (!_updating) UpdatePreview();
    }

    private void DeviceBox_OnSelectionChanged(object sender, SelectionChangedEventArgs e) => UpdatePreview();

    private void UpdatePreview()
    {
        if (!IsLoaded || _updating) return;
        CommandPreviewBox.Text = "scrcpy " + string.Join(' ', BuildArguments().Select(Quote));
    }

    private List<string> BuildArguments()
    {
        var arguments = new List<string>();
        var screenOff = ReadChecked("turn-screen-off");
        foreach (var definition in _definitions.Values)
        {
            if (string.IsNullOrEmpty(definition.Argument)) continue;
            if (screenOff && (definition.Key == "stay-awake" || definition.Key == "screen-off-timeout")) continue;
            if (definition.Kind == OptionKind.Check)
            {
                if (ReadChecked(definition.Key)) arguments.Add(definition.Argument);
                continue;
            }
            var value = ReadText(definition.Key).Trim();
            if (string.IsNullOrWhiteSpace(value) || value == DefaultChoice) continue;
            arguments.Add(definition.Argument.Replace("{0}", value, StringComparison.Ordinal));
        }
        if (screenOff) arguments.Add("--keep-active");
        if (DeviceBox.SelectedItem is string label && _deviceIds.TryGetValue(label, out var deviceId)) arguments.Add("--serial=" + deviceId);
        arguments.AddRange(SplitArguments(ExtraArgumentsBox.Text));
        return arguments;
    }

    private async void RunButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_scrcpyPath is null)
        {
            MessageBox.Show(this, "scrcpy.exe를 찾지 못했습니다. 설정 탭에서 위치를 지정하세요.", "실행", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        if (DeviceBox.SelectedItem is string selected && selected.StartsWith("(오프라인)", StringComparison.Ordinal))
        {
            MessageBox.Show(this, "고른 기기가 현재 연결돼 있지 않습니다. 기기 찾기로 연결한 뒤 실행하세요.", "실행", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (ReadChecked("turn-screen-off") && (ReadChecked("no-control") || SplitArguments(ExtraArgumentsBox.Text).Any(arg => arg is "--no-control" or "-n")))
        {
            MessageBox.Show(this, "화면 끄고 PC로 사용과 보기 전용은 함께 쓸 수 없습니다.", "실행", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var mouseMode = ReadText("mouse");
        if (mouseMode is "uhid" or "aoa")
        {
            var allow = MessageBox.Show(
                "마우스가 scrcpy 창에 캡처될 수 있습니다.\n빠져나오려면 Alt 또는 Windows 키를 누르세요. 다시 누르면 재캡처됩니다.\n\n이 설정으로 실행할까요?",
                "입력 캡처 안내", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (allow != MessageBoxResult.Yes) return;
        }

        RunButton.IsEnabled = false;
        try
        {
            var start = new ProcessStartInfo
            {
                FileName = _scrcpyPath,
                WorkingDirectory = Path.GetDirectoryName(_scrcpyPath)!,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            foreach (var argument in BuildArguments()) start.ArgumentList.Add(argument);
            Process.Start(start);
            SetStatus("scrcpy를 실행했습니다. 이 설정 창을 닫아도 미러링 창은 계속 유지됩니다.");
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, $"scrcpy 실행에 실패했습니다.\n\n{exception.Message}", "실행", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally { RunButton.IsEnabled = true; }
        await Task.CompletedTask;
    }

    private void CopyButton_OnClick(object sender, RoutedEventArgs e)
    {
        Clipboard.SetText(CommandPreviewBox.Text);
        SetStatus("명령어를 클립보드에 복사했습니다.");
    }

    private void ExtraArgumentsButton_OnClick(object sender, RoutedEventArgs e)
    {
        var dialog = new Window
        {
            Owner = this,
            Title = "직접 인자 추가",
            Width = 640,
            Height = 320,
            MinWidth = 480,
            MinHeight = 280,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.CanResize,
            Background = (System.Windows.Media.Brush)FindResource("Bg"),
            Foreground = (System.Windows.Media.Brush)FindResource("Text"),
            FontFamily = FontFamily,
            FontSize = FontSize,
        };

        foreach (var key in new object[] { "Bg", "Surface", "SurfaceRaised", "Line", "Text", "Muted", "Faint", "Accent" })
        {
            dialog.Resources[key] = FindResource(key);
        }
        dialog.Resources[typeof(Button)] = FindResource(typeof(Button));
        dialog.Resources[typeof(TextBox)] = FindResource(typeof(TextBox));

        var editor = new TextBox
        {
            Text = ExtraArgumentsBox.Text,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalContentAlignment = VerticalAlignment.Top,
            MinHeight = 132,
        };

        var content = new Grid { Margin = new Thickness(20) };
        content.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        content.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        content.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        content.Children.Add(new TextBlock
        {
            Text = "scrcpy에 추가할 인자를 입력하세요. 여러 인자는 공백 또는 줄바꿈으로 구분합니다.",
            Foreground = (System.Windows.Media.Brush)FindResource("Muted"),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 12),
        });
        Grid.SetRow(editor, 1);
        content.Children.Add(editor);

        var actions = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0),
        };
        var cancel = new Button { Content = "취소" };
        cancel.Click += (_, _) => dialog.DialogResult = false;
        var apply = new Button
        {
            Content = "적용",
            Background = (System.Windows.Media.Brush)FindResource("Accent"),
            Foreground = (System.Windows.Media.Brush)FindResource("Bg"),
            Padding = new Thickness(16, 6, 16, 6),
            Margin = new Thickness(8, 0, 0, 0),
        };
        apply.Click += (_, _) =>
        {
            ExtraArgumentsBox.Text = editor.Text.Trim();
            SetStatus(string.IsNullOrWhiteSpace(ExtraArgumentsBox.Text) ? "직접 인자를 비웠습니다." : "직접 인자를 적용했습니다.");
            dialog.DialogResult = true;
        };
        actions.Children.Add(cancel);
        actions.Children.Add(apply);
        Grid.SetRow(actions, 2);
        content.Children.Add(actions);

        dialog.Content = content;
        dialog.Loaded += (_, _) => editor.Focus();
        dialog.ShowDialog();
    }

    private void PresetBox_OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_updating || PresetBox.SelectedItem is not string name || name == "(선택 안 함)") return;
        if (_presets[name] is JsonObject values)
        {
            ApplyValues(values);
            SetStatus($"프리셋 ‘{name}’을 불러왔습니다.");
        }
    }

    private void SavePresetButton_OnClick(object sender, RoutedEventArgs e)
    {
        var name = PresetBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(name) || name == "(선택 안 함)")
        {
            SetStatus("저장할 프리셋 이름을 입력하거나 고르세요.");
            return;
        }
        _presets[name] = CaptureValues();
        SaveObject(PresetPath, _presets);
        ReloadPresetList(name);
        SetStatus($"프리셋 ‘{name}’을 저장했습니다.");
    }

    private void DeletePresetButton_OnClick(object sender, RoutedEventArgs e)
    {
        var name = PresetBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(name) || name == "(선택 안 함)" || !_presets.ContainsKey(name)) return;
        if (MessageBox.Show(this, $"프리셋 ‘{name}’을 삭제할까요?", "프리셋 삭제", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        _presets.Remove(name);
        SaveObject(PresetPath, _presets);
        ReloadPresetList();
        SetStatus($"프리셋 ‘{name}’을 삭제했습니다.");
    }

    private void ReloadPresetList(string? selected = null)
    {
        _updating = true;
        try
        {
            PresetBox.Items.Clear();
            PresetBox.Items.Add("(선택 안 함)");
            foreach (var name in _presets.Select(item => item.Key).OrderBy(name => name, StringComparer.Ordinal)) PresetBox.Items.Add(name);
            PresetBox.Text = selected ?? "(선택 안 함)";
        }
        finally { _updating = false; }
    }

    private JsonObject CaptureValues()
    {
        var values = new JsonObject();
        foreach (var definition in _definitions.Values.Where(item => item.Kind is not OptionKind.Path and not OptionKind.PhonePreference))
        {
            values[definition.Key] = definition.Kind == OptionKind.Check ? ReadChecked(definition.Key) : ReadText(definition.Key);
        }
        values["__extra"] = ExtraArgumentsBox.Text;
        return values;
    }

    private void RestoreLastValues()
    {
        var values = LoadObject(LastPath);
        if (values.Count > 0) ApplyValues(values);
    }

    private void ApplyValues(JsonObject values)
    {
        _updating = true;
        try
        {
            foreach (var definition in _definitions.Values)
            {
                if (!values.TryGetPropertyValue(definition.Key, out var value) || value is null || !_controls.TryGetValue(definition.Key, out var control)) continue;
                if (control is CheckBox box) box.IsChecked = ReadBool(value);
                else if (control is ComboBox combo) combo.Text = ReadString(value);
                else if (control is TextBox text) text.Text = ReadString(value);
            }
            if (values["__extra"] is not null) ExtraArgumentsBox.Text = ReadString(values["__extra"]);
        }
        finally { _updating = false; }
        UpdatePreview();
    }

    private bool ReadChecked(string key) => _controls.TryGetValue(key, out var control) && control is CheckBox box && box.IsChecked == true;
    private string ReadText(string key) => _controls.TryGetValue(key, out var control) switch
    {
        true when control is TextBox box => box.Text,
        true when control is ComboBox combo => combo.Text,
        _ => "",
    };

    private bool EnsureAdb(bool showMessage = true)
    {
        ResolveExecutables();
        if (_adbPath is not null) return true;
        if (showMessage) MessageBox.Show(this, "adb.exe를 찾지 못했습니다. 설정 탭에서 위치를 지정하세요.", "adb 필요", MessageBoxButton.OK, MessageBoxImage.Error);
        return false;
    }

    private Task<CommandResult> RunAdbAsync(IEnumerable<string> arguments) => _adbPath is null
        ? Task.FromResult(new CommandResult(-1, "adb.exe를 찾지 못했습니다."))
        : RunProcessAsync(_adbPath, arguments);

    private static async Task<CommandResult> RunProcessAsync(string executable, IEnumerable<string> arguments)
    {
        try
        {
            var start = new ProcessStartInfo
            {
                FileName = executable,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            foreach (var argument in arguments) start.ArgumentList.Add(argument);
            using var process = Process.Start(start);
            if (process is null) return new CommandResult(-1, "프로세스를 시작하지 못했습니다.");
            var stdout = process.StandardOutput.ReadToEndAsync();
            var stderr = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();
            return new CommandResult(process.ExitCode, (await stdout) + (await stderr));
        }
        catch (Exception exception) { return new CommandResult(-1, exception.Message); }
    }

    private static async Task<bool> TcpOpenAsync(string host, int port)
    {
        try
        {
            using var client = new TcpClient();
            await client.ConnectAsync(host, port).WaitAsync(TimeSpan.FromSeconds(1));
            return client.Connected;
        }
        catch { return false; }
    }

    private static IEnumerable<string> SplitArguments(string text) => Regex.Matches(text ?? "", "\\\"([^\\\"]*)\\\"|'([^']*)'|(\\S+)")
        .Select(match => match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Success ? match.Groups[2].Value : match.Groups[3].Value);

    private static string Quote(string argument) => argument.Contains(' ') ? '"' + argument.Replace("\"", "\\\"") + '"' : argument;
    private void SetStatus(string message) => StatusText.Text = message;

    protected override void OnClosing(CancelEventArgs e)
    {
        SaveObject(LastPath, CaptureValues());
        base.OnClosing(e);
    }

    private static JsonObject LoadObject(string path)
    {
        try { return JsonNode.Parse(File.ReadAllText(path, Encoding.UTF8)) as JsonObject ?? new JsonObject(); }
        catch { return new JsonObject(); }
    }

    private static void SaveObject(string path, JsonObject value)
    {
        try { File.WriteAllText(path, value.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), new UTF8Encoding(false)); }
        catch { }
    }

    private static string ReadString(JsonNode? value)
    {
        if (value is JsonValue json && json.TryGetValue<string>(out var text)) return text;
        return value?.ToString() ?? "";
    }

    private static bool ReadBool(JsonNode? value)
    {
        if (value is JsonValue json && json.TryGetValue<bool>(out var flag)) return flag;
        return bool.TryParse(ReadString(value), out var parsed) && parsed;
    }

    private static JsonObject DefaultPresets() => new()
    {
        ["평소용"] = new JsonObject { ["max-size"] = "1850", ["max-fps"] = "120", ["video-bit-rate"] = "8M", ["keyboard"] = "uhid", ["screen-off-timeout"] = "500", ["__extra"] = "" },
        ["고화질"] = new JsonObject { ["max-size"] = "1920", ["max-fps"] = "120", ["video-bit-rate"] = "16M", ["video-codec"] = "h265", ["keyboard"] = "uhid", ["screen-off-timeout"] = "500", ["__extra"] = "" },
        ["가볍게"] = new JsonObject { ["max-size"] = "1080", ["max-fps"] = "60", ["video-bit-rate"] = "4M", ["video-codec"] = "h265", ["keyboard"] = "uhid", ["turn-screen-off"] = true, ["__extra"] = "" },
        ["가로화면"] = new JsonObject { ["max-size"] = "", ["max-fps"] = "120", ["video-bit-rate"] = "8M", ["keyboard"] = "uhid", ["new-display"] = "1920x1080", ["__extra"] = "" },
    };

    private static IReadOnlyList<OptionDefinition> Definitions() =>
    [
        new("화면", "max-size", "해상도 상한", OptionKind.EditableCombo, "--max-size={0}", "1850", Items: [DefaultChoice, "3088", "2560", "1920", "1850", "1600", "1440", "1280", "1080", "720"], Hint: "긴 변 픽셀 하나만 넣습니다. 1920=FHD, 1440=HD+"),
        new("화면", "max-fps", "최대 프레임", OptionKind.EditableCombo, "--max-fps={0}", "120", Items: [DefaultChoice, "144", "120", "90", "60", "30"], Hint: "높을수록 부드럽지만 데이터·발열이 증가합니다."),
        new("화면", "video-bit-rate", "화질", OptionKind.EditableCombo, "--video-bit-rate={0}", "8M", Items: [DefaultChoice, "32M", "16M", "12M", "8M", "4M", "2M"], Hint: "높을수록 선명하지만 지연·데이터가 증가합니다."),
        new("화면", "video-codec", "영상 코덱", OptionKind.Combo, "--video-codec={0}", DefaultChoice, Items: [DefaultChoice, "h264", "h265", "av1"], Hint: "h265는 같은 화질에서 데이터가 적습니다."),
        new("화면", "orientation", "화면 방향", OptionKind.Combo, "--orientation={0}", DefaultChoice, Items: [DefaultChoice, "0", "90", "180", "270", "flip0", "flip90", "flip180", "flip270"], Hint: "창에 보이는 방향만 회전합니다."),
        new("화면", "crop", "잘라내기", OptionKind.Text, "--crop={0}", Hint: "폭:높이:x:y   예) 1080:1080:0:420"),
        new("화면", "new-display", "가로 화면 (16:9)", OptionKind.EditableCombo, "--new-display={0}", DefaultChoice, Items: [DefaultChoice, "1920x1080", "1600x900", "2560x1440", "1280x720"], Hint: "폰과 별개인 가로 화면을 새로 만듭니다."),
        new("창", "fullscreen", "전체화면으로 시작", OptionKind.Check, "--fullscreen", Hint: "실행 뒤 Ctrl+F로도 전환합니다."),
        new("창", "always-on-top", "항상 위에", OptionKind.Check, "--always-on-top", Hint: "다른 창에 가려지지 않습니다."),
        new("창", "borderless", "테두리 없애기", OptionKind.Check, "--window-borderless", Hint: "제목표시줄·테두리를 제거합니다."),
        new("창", "window-title", "창 제목", OptionKind.Text, "--window-title={0}", Hint: "비우면 폰 모델명입니다."),
        new("창", "window-width", "창 너비", OptionKind.Text, "--window-width={0}", Hint: "픽셀. 비우면 자동입니다."),
        new("창", "window-height", "창 높이", OptionKind.Text, "--window-height={0}", Hint: "픽셀. 비우면 자동입니다."),
        new("전원", "turn-screen-off", "화면 끄고 PC로 사용", OptionKind.Check, "--turn-screen-off", Hint: "화면을 끄고 활성 상태를 유지합니다."),
        new("전원", "stay-awake", "충전 중 활성 유지", OptionKind.Check, "--stay-awake", Hint: "충전 중일 때만 작동합니다."),
        new("전원", "screen-off-timeout", "화면 자동 꺼짐 시간", OptionKind.Text, "--screen-off-timeout={0}", "500", Hint: "초 단위입니다."),
        new("전원", "no-power-on", "시작할 때 안 켜기", OptionKind.Check, "--no-power-on"),
        new("전원", "power-off-on-close", "닫을 때 폰 화면 끄기", OptionKind.Check, "--power-off-on-close"),
        new("전원", "disable-screensaver", "PC 화면보호기 끄기", OptionKind.Check, "--disable-screensaver"),
        new("입력", "keyboard", "키보드 방식", OptionKind.Combo, "--keyboard={0}", "uhid", Items: [DefaultChoice, "uhid", "aoa", "sdk", "disabled"], Hint: "uhid는 한글 입력을 지원합니다. 한/영은 Shift+Space."),
        new("입력", "mouse", "마우스 방식", OptionKind.Combo, "--mouse={0}", DefaultChoice, Items: [DefaultChoice, "uhid", "aoa", "sdk", "disabled"], Hint: "uhid·aoa는 실행 전 탈출 방법을 안내합니다."),
        new("입력", "show-touches", "터치 지점 표시", OptionKind.Check, "--show-touches"),
        new("입력", "prefer-text", "텍스트 입력 우선", OptionKind.Check, "--prefer-text"),
        new("입력", "no-key-repeat", "키 반복 끄기", OptionKind.Check, "--no-key-repeat"),
        new("입력", "no-control", "보기 전용", OptionKind.Check, "--no-control"),
        new("입력", "ime-with-hw", "폰 화면 자판 표시", OptionKind.PhonePreference, Hint: "즉시 폰 설정을 바꿉니다.", SettingNamespace: "secure", SettingKey: "show_ime_with_hard_keyboard"),
        new("소리", "no-audio", "소리 끄기", OptionKind.Check, "--no-audio"),
        new("소리", "audio-codec", "오디오 코덱", OptionKind.Combo, "--audio-codec={0}", DefaultChoice, Items: [DefaultChoice, "opus", "aac", "flac", "raw"]),
        new("소리", "audio-bit-rate", "소리 비트레이트", OptionKind.Text, "--audio-bit-rate={0}", Hint: "예: 128K"),
        new("소리", "audio-source", "소리 원본", OptionKind.Combo, "--audio-source={0}", DefaultChoice, Items: [DefaultChoice, "output", "playback", "mic"]),
        new("소리", "audio-dup", "폰에서도 같이 재생", OptionKind.Check, "--audio-dup"),
        new("녹화", "record", "녹화 파일", OptionKind.Text, "--record={0}", Hint: "예: C:\\rec\\phone.mp4"),
        new("녹화", "record-format", "녹화 형식", OptionKind.Combo, "--record-format={0}", DefaultChoice, Items: [DefaultChoice, "mp4", "mkv", "m4a", "mka", "opus", "aac", "flac", "wav"]),
        new("녹화", "time-limit", "자동 종료", OptionKind.Text, "--time-limit={0}", Hint: "초 단위. 예: 600"),
        new("녹화", "no-video-playback", "영상 표시 안 함", OptionKind.Check, "--no-video-playback"),
        new("기타", "start-app", "시작할 앱", OptionKind.Text, "--start-app={0}", Hint: "패키지명 또는 ?이름"),
        new("기타", "display-id", "화면 번호", OptionKind.Text, "--display-id={0}"),
        new("기타", "render-driver", "렌더러", OptionKind.Combo, "--render-driver={0}", DefaultChoice, Items: [DefaultChoice, "direct3d11", "direct3d", "opengl", "opengles2", "software"]),
        new("설정", "scrcpyPath", "scrcpy.exe 위치", OptionKind.Path, Hint: "여러 버전이 있으면 가장 높은 버전을 고릅니다."),
        new("설정", "adbPath", "adb.exe 위치", OptionKind.Path, Hint: "scrcpy 폴더 안에 같이 있는 경우가 많습니다."),
    ];

    private sealed record DeviceInfo(string Id, string State, string Model);
    private sealed record CommandResult(int ExitCode, string Output);
}
