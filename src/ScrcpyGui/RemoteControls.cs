using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using static ScrcpyGui.RemoteNative;

namespace ScrcpyGui;

internal sealed partial class RemoteControls : IDisposable
{
    private readonly Window _owner;
    private readonly string _path;
    private RemoteSettings _settings;
    private readonly RemoteRelay _relay = new();
    private readonly DispatcherTimer _timer;
    private readonly Dictionary<RemoteAction, RemoteButtonWindow> _buttons = new();
    private readonly LogicalPointerWindow _pointer = new();
    private readonly ComboBox _targets = new() { MinWidth = 280, DisplayMemberPath = "" };
    private readonly TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightSteelBlue, Margin = new Thickness(0, 12, 0, 12) };
    private readonly TextBlock _targetStatus = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 12) };
    private readonly StackPanel _form = new();
    private readonly StackPanel _advanced = new();
    private readonly StackPanel _scrollSettings = new();
    private readonly TabControl _settingsTabs = new() { Background = Brushes.Transparent, BorderThickness = new Thickness(0), Padding = new Thickness(0, 12, 0, 0) };
    private readonly TextBlock _scrollSummary = new() { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightSteelBlue, Margin = new Thickness(0, 6, 0, 12) };
    private readonly Canvas _preview = new() { Width = 340, Height = 245, HorizontalAlignment = HorizontalAlignment.Left };
    private readonly TextBlock _runState = new() { FontSize = 17, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 8), TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock _noticeBanner = new() { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightSteelBlue, Margin = new Thickness(0, 4, 0, 4), Visibility = Visibility.Collapsed };
    private MirrorTarget? _target;
    private bool _enabled, _calibrated, _building, _visible, _disposed;
    private bool _refreshingTargets, _updatingTargets;
    private long _revision;
    private PixelRect _lastWindow, _lastClient;
    private double _calibratedAspect;
    private string _layoutMessage = "";
    private string _loadError = "";
    private string _notice = "";
    private WindowState _ownerRestoreState;
    private bool _pointNeedsReview;
    private long _toolbarUntil;
    private bool _covered;
    private long _nextCoverCheck;
    private long _nextRefresh;
    public FrameworkElement Page { get; }
    internal bool HasSelectedTarget => _target is not null;
    public bool KeepRunningWhenSettingsClosed => _visible && _target is not null && Valid(_target);

    public RemoteControls(Window owner, string directory, Action reveal)
    {
        _owner = owner; _path = Path.Combine(directory, "scrcpy-gui-remote.json");
        _ownerRestoreState = owner.WindowState == WindowState.Minimized ? WindowState.Normal : owner.WindowState;
        try { _settings = RemoteSettings.Load(_path); }
        catch (Exception ex) { _settings = new(); _loadError = ex.Message; }
        var page = new StackPanel { Margin = new Thickness(20) };
        page.Children.Add(new TextBlock { Text = "휴대폰 외부 조작판", FontSize = 24, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 14) });
        page.Children.Add(new TextBlock { Text = "미러링 창이 하나면 자동으로 연결 대상을 고릅니다. ‘사용하기’로 조작판을 켜세요.", TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightSlateGray, Margin = new Thickness(0, 0, 0, 12) });
        var targetSection = new StackPanel();
        page.Children.Add(new Border { Child = targetSection, Padding = new Thickness(12), Background = new SolidColorBrush(Color.FromRgb(22, 22, 24)), CornerRadius = new CornerRadius(10), Margin = new Thickness(0, 0, 0, 12) });
        var targetRow = new DockPanel();
        var refreshActions = new WrapPanel(); AddButton(refreshActions, "다시 찾기", async () => await Refresh());
        DockPanel.SetDock(refreshActions, Dock.Right); targetRow.Children.Add(refreshActions);
        _targetStatus.Margin = new Thickness(0, 0, 8, 0); _targetStatus.VerticalAlignment = VerticalAlignment.Center;
        targetRow.Children.Add(_targetStatus); targetSection.Children.Add(targetRow);
        targetSection.Children.Add(_targets);
        _targetStatus.Text = string.IsNullOrEmpty(_settings.TargetHint) ? "미러링 창을 선택하세요." : $"직전 대상: {_settings.TargetHint} · 현재 창을 다시 선택하세요.";
        _targets.SelectionChanged += (_, _) =>
        {
            if (!_updatingTargets) TargetChanged();
        };
        _targets.DropDownOpened += async (_, _) => await Refresh();
        var tabStyle = new Style(typeof(TabItem));
        tabStyle.Setters.Add(new Setter(UIElement.VisibilityProperty, Visibility.Visible));
        tabStyle.Setters.Add(new Setter(Control.ForegroundProperty, Brushes.Gainsboro));
        tabStyle.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(Color.FromRgb(30, 34, 42))));
        tabStyle.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(12, 10, 12, 10)));
        var tabBorder = new FrameworkElementFactory(typeof(Border), "TabSurface");
        tabBorder.SetValue(Border.BackgroundProperty, new SolidColorBrush(Color.FromRgb(30, 34, 42)));
        tabBorder.SetValue(Border.CornerRadiusProperty, new CornerRadius(7));
        tabBorder.SetValue(FrameworkElement.MarginProperty, new Thickness(0, 0, 4, 4));
        var tabHeader = new FrameworkElementFactory(typeof(ContentPresenter));
        tabHeader.SetValue(ContentPresenter.ContentSourceProperty, "Header");
        tabHeader.SetValue(FrameworkElement.MarginProperty, new Thickness(12, 12, 12, 12));
        tabBorder.AppendChild(tabHeader);
        var tabTemplate = new ControlTemplate(typeof(TabItem)) { VisualTree = tabBorder };
        var selectedTab = new Trigger { Property = TabItem.IsSelectedProperty, Value = true };
        selectedTab.Setters.Add(new Setter(Border.BackgroundProperty, new SolidColorBrush(Color.FromRgb(40, 76, 120)), "TabSurface"));
        tabTemplate.Triggers.Add(selectedTab);
        tabStyle.Setters.Add(new Setter(Control.TemplateProperty, tabTemplate));
        _settingsTabs.Resources.Add(typeof(TabItem), tabStyle);
        page.Children.Add(_settingsTabs);
        var usageSection = SettingsTab("사용");
        var layoutSection = SettingsTab("배치·크기");
        var layoutBody = new WrapPanel();
        _form.Width = 360; _form.Margin = new Thickness(0, 0, 10, 0);
        layoutBody.Children.Add(_form);
        layoutBody.Children.Add(new Viewbox { Width = 200, Height = 180, Stretch = Stretch.Uniform, Child = _preview, VerticalAlignment = VerticalAlignment.Top });
        layoutSection.Children.Add(layoutBody);
        BuildAppearanceTabs();
        usageSection.Children.Add(new TextBlock { Text = "누르는 방법", FontSize = 17, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 6, 0, 10) });
        var activation = new ComboBox { ItemsSource = new[] { "바라보면 누르기 (드웰)", "클릭해서 누르기" }, SelectedIndex = _settings.Activation == "click" ? 1 : 0, MinHeight = 44, Margin = new Thickness(0, 4, 0, 10) };
        activation.SelectionChanged += (_, _) => Change(() => _settings.Activation = activation.SelectedIndex == 1 ? "click" : "dwell");
        usageSection.Children.Add(activation);
        var repeat = new CheckBox { Content = "스크롤 버튼은 계속 바라보는 동안 반복하기", IsChecked = _settings.Repeat, Foreground = Brushes.Gainsboro, Margin = new Thickness(0, 8, 0, 10) };
        repeat.Click += (_, _) => Change(() => _settings.Repeat = repeat.IsChecked == true);
        usageSection.Children.Add(repeat);
        usageSection.Children.Add(new TextBlock { Text = "뒤로 · 홈 · 최근 앱은 한 번만 눌립니다.\n스크롤은 기본으로 휴대폰 화면 가운데에서 실행합니다.", TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightSteelBlue });
        var scrollSection = SettingsTab("속도·스크롤");
        scrollSection.Children.Add(_scrollSummary);
        AddButton(scrollSection, "new-alt 기본값 적용", () =>
        {
            Change(() => { _settings.ScrollMode = "atomic"; _settings.DwellMs = 300; _settings.RepeatMs = 300; _settings.SettleMs = 20; _settings.Notches = 1; });
            BuildScrollSettings();
        });
        scrollSection.Children.Add(_scrollSettings);
        BuildScrollSettings();
        SettingsTab("고급").Children.Add(_advanced);
        Check("클릭 모드에서 누르고 있는 동안 스크롤 반복", _settings.HoldRepeat, v => _settings.HoldRepeat = v, _advanced);
        Check("스크롤할 때 휴대폰 창을 앞으로 가져오기", _settings.BringForward, v => _settings.BringForward = v, _advanced);
        var advancedActions = new System.Windows.Controls.Primitives.UniformGrid { Columns = 2, Margin = new Thickness(0, 6, 0, 0) };
        _advanced.Children.Add(advancedActions);
        AddButton(advancedActions, "스크롤할 위치를 직접 지정하기", Calibrate);
        AddButton(advancedActions, "저장한 스크롤 위치 사용하기", () =>
        {
            Pause();
            if (_target is null || !Valid(_target) || _settings.CalibratedAspect <= 0) { Notice("저장된 영상 지점이 없습니다. 먼저 지정하세요."); return; }
            var client = ClientBounds(_target.Handle);
            if (Math.Abs(client.Width / client.Height / _settings.CalibratedAspect - 1) > .02) { Notice("영상 비율이 다릅니다. 영역과 지점을 다시 지정하세요."); return; }
            ConfirmCalibration();
        });
        AddButton(advancedActions, "기본 위치로 되돌리기 · 화면 가운데", () =>
        {
            Pause(); if (_target is null || !Valid(_target)) { _targetStatus.Text = "먼저 미러링 창을 선택하세요."; return; }
            _settings.VideoLeft = _settings.VideoTop = 0; _settings.VideoRight = _settings.VideoBottom = 1;
            _settings.U = _settings.V = .5; ConfirmCalibration(); Save();
        });
        AddButton(advancedActions, "창과 버튼을 화면 안으로 옮기기", FitTogether);
        var dock = new StackPanel { Margin = new Thickness(12, 8, 12, 8) };
        var actions = new WrapPanel();
        AddButton(actions, "▶ 사용하기", Start);
        AddButton(actions, "Ⅱ 일시 정지", Pause);
        AddButton(actions, "조작판 끄기", HideControls);
        dock.Children.Add(_runState); dock.Children.Add(actions);
        dock.Children.Add(_noticeBanner);
        dock.Children.Add(new Expander { Header = "상태·도움말", Content = _status, Foreground = Brushes.LightSlateGray, Margin = new Thickness(0, 6, 0, 0) });
        var root = new Grid();
        root.SetValue(TextElement.ForegroundProperty, Brushes.Gainsboro);
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.Children.Add(new ScrollViewer { Content = page, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
        var dockBorder = new Border { Background = new SolidColorBrush(Color.FromRgb(22, 22, 24)), Child = dock, BorderBrush = Brushes.DimGray, BorderThickness = new Thickness(0, 1, 0, 0) };
        Grid.SetRow(dockBorder, 1); root.Children.Add(dockBorder); Page = root;
        root.IsVisibleChanged += async (_, _) => { if (root.IsVisible) await Refresh(); };
        BuildForm();
        _owner.IsEnabledChanged += OwnerEnabledChanged;
        _owner.StateChanged += OwnerStateChanged;
        _timer = new DispatcherTimer(TimeSpan.FromMilliseconds(40), DispatcherPriority.Normal, (_, _) =>
        {
            Update();
            AnimateFeedbackPreview();
            if (Page.IsVisible && Environment.TickCount64 >= _nextRefresh && !_targets.IsDropDownOpen)
            {
                _nextRefresh = Environment.TickCount64 + 3000;
                _ = Refresh();
            }
            if (_relay.TakeUtility() is { } utility)
            {
                if (utility == RemoteAction.Stop) { if (_enabled) Pause(); else Start(); return; }
                Pause();
                if (utility == RemoteAction.Settings && _owner.IsEnabled)
                {
                    RestoreOwnerState(); reveal();
                    if (!_owner.IsVisible) _owner.Show();
                    _owner.Activate();
                }
            }
        }, owner.Dispatcher);
    }

    private void BuildForm()
    {
        _building = true; _form.Children.Clear();
        Choice("버튼 묶음", ["나눠 놓기 · 아래에 3개, 옆에 스크롤", "한 줄로 놓기 · 옆에 5개"], _settings.Layout == "combined" ? 1 : 0, i => _settings.Layout = i == 1 ? "combined" : "split", true);
        Choice("휴대폰의 어느 쪽에 놓을까요?", ["왼쪽", "오른쪽"], _settings.Choice.Side == "left" ? 0 : 1, i => _settings.Choice.Side = i == 0 ? "left" : "right");
        Choice("옆 버튼의 높이", ["위쪽", "가운데", "아래쪽"], Array.IndexOf(new[] { "top", "center", "bottom" }, _settings.Choice.Align), i => _settings.Choice.Align = new[] { "top", "center", "bottom" }[i]);
        if (_settings.Layout == "combined") Choice("스크롤 두 개는 어디에 둘까요?", ["뒤로 · 홈 · 최근 앱 위에", "뒤로 · 홈 · 최근 앱 아래에"], _settings.Choice.ScrollPosition == "top" ? 0 : 1, i => _settings.Choice.ScrollPosition = i == 0 ? "top" : "bottom");
        Choice("크기 기준", ["고정 크기", "휴대폰 창 너비에 맞추기"], _settings.SizeMode == "relative" ? 1 : 0, i => _settings.SizeMode = i == 1 ? "relative" : "fixed", true);
        if (_settings.SizeMode == "relative") Number("창 너비 대비 버튼 높이 (%)", _settings.RelativeSizePercent, 5, 50, v => _settings.RelativeSizePercent = v);
        else Number("버튼 높이 (DIP)", _settings.Size, 32, 200, v => _settings.Size = v);
        Number("가로 비율 (%) · 100이면 정사각형", _settings.WidthPercent, 50, 250, v => _settings.WidthPercent = v);
        Number("휴대폰 창과 버튼 사이 여백 (DIP)", _settings.Distance, 0, 160, v => _settings.Distance = v);
        Number("버튼 사이 간격 (DIP)", _settings.Gap, 0, 80, v => _settings.Gap = v);
        Number("두 묶음 사이 간격 (DIP)", _settings.GroupGap, 0, 120, v => _settings.GroupGap = v);
        UpdatePreview();
        _building = false;
    }
    private void Choice(string label, string[] values, int selected, Action<int> apply, bool rebuild = false)
    {
        var box = new ComboBox { ItemsSource = values, SelectedIndex = selected, MinWidth = 220, MinHeight = 44, Margin = new Thickness(0, 4, 0, 10) };
        _form.Children.Add(new TextBlock { Text = label }); _form.Children.Add(box);
        box.SelectionChanged += (_, _) => { if (_building || box.SelectedIndex < 0) return; Change(() => apply(box.SelectedIndex)); if (rebuild) BuildForm(); };
    }
    private void Number(string label, int value, int min, int max, Action<int> apply, Panel? parent = null)
    {
        var row = new Grid { Margin = new Thickness(0, 5, 0, 9), ToolTip = $"{min} ～ {max}" };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 8, 0) });
        var editor = new StackPanel { Orientation = Orientation.Horizontal };
        var input = new TextBox { Text = value.ToString(), Tag = label, Width = 68, MinHeight = 44, VerticalContentAlignment = VerticalAlignment.Center, HorizontalContentAlignment = HorizontalAlignment.Center };
        System.Windows.Automation.AutomationProperties.SetName(input, label);
        var step = max >= 500 ? 10 : 1;
        var current = value;
        void SetValue(int number)
        {
            number = Math.Clamp(number, min, max); input.Text = number.ToString();
            if (_building || number == current) return;
            current = number; Change(() => apply(number)); UpdateScrollSummary();
        }
        var minus = new Button { Content = "−", FontSize = 18, MinWidth = 44, MinHeight = 44, Background = new SolidColorBrush(Color.FromRgb(30, 34, 42)), Foreground = Brushes.Gainsboro, BorderBrush = Brushes.DimGray, Margin = new Thickness(0, 0, 4, 0) };
        var plus = new Button { Content = "+", FontSize = 18, MinWidth = 44, MinHeight = 44, Background = new SolidColorBrush(Color.FromRgb(30, 34, 42)), Foreground = Brushes.Gainsboro, BorderBrush = Brushes.DimGray, Margin = new Thickness(4, 0, 0, 0) };
        System.Windows.Automation.AutomationProperties.SetName(minus, label + " 줄이기");
        System.Windows.Automation.AutomationProperties.SetName(plus, label + " 늘리기");
        minus.Click += (_, _) => SetValue(current - step); plus.Click += (_, _) => SetValue(current + step);
        editor.Children.Add(minus); editor.Children.Add(input); editor.Children.Add(plus);
        Grid.SetColumn(editor, 1); row.Children.Add(editor);
        void Commit()
        {
            if (int.TryParse(input.Text, out var number)) SetValue(number);
            else input.Text = current.ToString();
        }
        input.LostKeyboardFocus += (_, _) => Commit();
        input.KeyDown += (_, e) => { if (e.Key == Key.Enter) { Commit(); e.Handled = true; } };
        (parent ?? _form).Children.Add(row);
    }
    private void BuildScrollSettings()
    {
        _building = true; _scrollSettings.Children.Clear();
        var mode = new ComboBox { ItemsSource = new[] { "빠른 왕복 · new-alt 방식", "단계별 왕복 · 전후 대기 지정" }, SelectedIndex = _settings.ScrollMode == "staged" ? 1 : 0, MinHeight = 44, Margin = new Thickness(0, 4, 0, 12) };
        _scrollSettings.Children.Add(mode);
        mode.SelectionChanged += (_, _) => { if (_building) return; Change(() => _settings.ScrollMode = mode.SelectedIndex == 1 ? "staged" : "atomic"); BuildScrollSettings(); };
        Number("처음 바라보는 시간 (ms) · 작을수록 빨리 시작", _settings.DwellMs, 0, 3000, v => _settings.DwellMs = v, _scrollSettings);
        Number("반복 사이 쉬는 시간 (ms) · 작을수록 빠르게 반복", _settings.RepeatMs, 0, 3000, v => _settings.RepeatMs = v, _scrollSettings);
        Number("한 번에 스크롤할 양 (휠 칸)", _settings.Notches, 1, 10, v => _settings.Notches = v, _scrollSettings);
        if (_settings.ScrollMode == "atomic")
            Number("커서 복귀 후 안정화 대기 (ms)", _settings.SettleMs, 0, 500, v => _settings.SettleMs = v, _scrollSettings);
        else
        {
            Number("휴대폰에 도착한 뒤 휠 전 대기 (ms)", _settings.ArrivalMs, 0, 500, v => _settings.ArrivalMs = v, _scrollSettings);
            Number("휠 입력 후 커서 복귀 전 대기 (ms)", _settings.AfterMs, 0, 500, v => _settings.AfterMs = v, _scrollSettings);
        }
        _building = false; UpdateScrollSummary();
    }
    private void UpdateScrollSummary()
    {
        var delay = _settings.RepeatMs + (_settings.ScrollMode == "atomic" ? _settings.SettleMs : _settings.ArrivalMs + _settings.AfterMs);
        _scrollSummary.Text = $"첫 응시 {_settings.DwellMs}ms · 한 번에 {_settings.Notches}칸 · 반복 대기 합계 {delay}ms\nWindows 처리 시간이 더해집니다. 0ms는 추가 대기 없음입니다.";
    }
    private void Check(string label, bool value, Action<bool> apply, Panel? parent = null)
    {
        var box = new CheckBox { Content = label, IsChecked = value, Foreground = Brushes.Gainsboro, Margin = new Thickness(0, 8, 0, 12) };
        (parent ?? _form).Children.Add(box);
        box.Click += (_, _) => Change(() => apply(box.IsChecked == true));
    }
    private static void AddButton(Panel panel, string text, Action action)
    {
        var button = new Button { Content = text, HorizontalAlignment = HorizontalAlignment.Left, MinHeight = 44, Padding = new Thickness(14, 8, 14, 8), Margin = new Thickness(0, 3, 8, 5), Background = new SolidColorBrush(Color.FromRgb(26, 26, 29)), BorderBrush = Brushes.DimGray };
        if (panel is System.Windows.Controls.Primitives.UniformGrid)
        {
            button.HorizontalAlignment = HorizontalAlignment.Stretch;
            button.MinHeight = 64;
            button.Margin = new Thickness(0, 0, 10, 10);
            button.Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center };
        }
        button.Click += (_, _) => action(); panel.Children.Add(button);
    }
    private void UpdatePreview()
    {
        _preview.Children.Clear();
        var phone = new PixelRect(0, 0, 400, 800);
        var positions = RemoteLayout.Calculate(_settings, phone, 1).Concat(RemoteLayout.Utilities(_settings, phone, 1)).ToArray();
        var bounds = positions.Select(p => p.Bounds).Append(phone).ToArray();
        var left = bounds.Min(b => b.X); var top = bounds.Min(b => b.Y);
        var factor = Math.Min(320 / (bounds.Max(b => b.Right) - left), 225 / (bounds.Max(b => b.Bottom) - top));
        var screen = new Border { Width = phone.Width * factor, Height = phone.Height * factor, CornerRadius = new CornerRadius(8), Background = new SolidColorBrush(Color.FromRgb(12, 15, 23)), BorderBrush = Brushes.SlateGray, BorderThickness = new Thickness(1), Child = new TextBlock { Text = "휴대폰\n화면", Foreground = Brushes.LightSteelBlue, VerticalAlignment = VerticalAlignment.Center, TextAlignment = TextAlignment.Center } };
        Canvas.SetLeft(screen, 10 - left * factor); Canvas.SetTop(screen, 10 - top * factor); _preview.Children.Add(screen);
        foreach (var placement in positions)
        {
            var visual = new RemoteButtonVisual { Width = placement.Bounds.Width, Height = placement.Bounds.Height };
            visual.Paint(_settings, placement.Action, .55, true, true);
            var button = new Viewbox { Width = placement.Bounds.Width * factor, Height = placement.Bounds.Height * factor, Child = visual };
            Canvas.SetLeft(button, 10 + (placement.Bounds.X - left) * factor); Canvas.SetTop(button, 10 + (placement.Bounds.Y - top) * factor); _preview.Children.Add(button);
        }
    }
    private void OwnerEnabledChanged(object sender, DependencyPropertyChangedEventArgs e) { if (!_owner.IsEnabled) Pause(); }
    private void OwnerStateChanged(object? sender, EventArgs e) { if (_owner.WindowState != WindowState.Minimized) _ownerRestoreState = _owner.WindowState; }
    internal void RestoreOwnerState() { if (_owner.WindowState == WindowState.Minimized) _owner.WindowState = _ownerRestoreState; }
    private void HideControls()
    {
        Pause(); _visible = false;
        foreach (var button in _buttons.Values) button.Hide();
        _pointer.Hide();
    }
    private void Notice(string text) { _notice = text; _status.Text = text; _noticeBanner.Text = text; _noticeBanner.Visibility = Visibility.Visible; }
    private void Change(Action apply)
    {
        var resume = _enabled;
        Pause(); _notice = ""; apply(); Save(); _revision++; _lastWindow = default;
        _enabled = resume && _calibrated; UpdatePreview(); Update();
    }
    private void Save()
    {
        if (_loadError.Length != 0) { Notice(_loadError + " 기존 파일을 보존했습니다."); return; }
        try { _settings.Save(_path); }
        catch (Exception ex) { Notice("설정 저장 실패: " + ex.Message); }
    }
    public async Task Refresh()
    {
        if (_disposed || _refreshingTargets) return;
        _refreshingTargets = true;
        if (_target is null) _targetStatus.Text = "열린 미러링 창을 찾는 중…";
        try
        {
            var targets = await Task.Run(Enumerate);
            if (_disposed) return;
            ApplyTargets(targets);
        }
        catch (Exception ex) { _targetStatus.Text = "창 목록 읽기 실패: " + ex.Message; }
        finally { _refreshingTargets = false; }
    }
    private void TargetChanged()
    {
        Pause(); _target = _targets.SelectedItem as MirrorTarget; _calibrated = false; _lastWindow = default;
        _notice = ""; _pointNeedsReview = false; _covered = false; _nextCoverCheck = 0;
        _targetStatus.Text = _target is null ? "미러링 창을 선택하세요." : string.IsNullOrEmpty(_target.Error) ? "영상 지점을 확인하세요." : _target.Error;
        if (_target is not null && _target.Error.Length == 0 && Valid(_target)) PrepareScrollPoint();
        Update();
    }
    internal void ApplyTargets(IReadOnlyList<MirrorTarget> targets)
    {
        var previous = _target;
        var retained = previous is null ? null : targets.FirstOrDefault(t =>
            t.Handle == previous.Handle && t.Pid == previous.Pid && t.Started == previous.Started);
        _updatingTargets = true;
        var selected = retained ?? (targets.Count == 1 ? targets[0] : null);
        try { _targets.ItemsSource = targets; _targets.SelectedItem = selected; _targets.Visibility = targets.Count > 1 ? Visibility.Visible : Visibility.Collapsed; }
        finally { _updatingTargets = false; }
        if (retained is not null)
        {
            _target = retained;
            _targetStatus.Text = retained.Error.Length != 0 ? retained.Error : $"선택한 미러링 창: {retained.Title}";
        }
        else
        {
            TargetChanged();
            _targetStatus.Text = targets.Count == 0 ? "미러링 창을 기다리는 중 · 창을 열면 자동으로 찾습니다." : selected is not null ? selected.Error.Length != 0 ? selected.Error : $"자동 선택 · {selected.Title}" : "미러링 창이 여러 개입니다. 조작할 창을 골라 주세요.";
        }
    }
    private void Start()
    {
        if (_loadError.Length != 0) { Notice(_loadError); return; }
        if (_target is null || !Valid(_target)) { Notice("미러링 창을 먼저 선택하세요."); return; }
        if (_target.Error.Length != 0) { Notice(_target.Error); return; }
        if (_pointNeedsReview) { Notice("영상 방향이 바뀌었습니다. 고급 설정에서 스크롤 위치를 다시 확인해 주세요."); return; }
        if (!_calibrated) PrepareScrollPoint();
        if (!_relay.View.InputReady) { Notice("입력 준비가 되지 않았습니다. " + _relay.View.Status); return; }
        try { Focus(_target); }
        catch (Exception ex) { Notice(ex.Message); return; }
        _notice = "";
        _visible = true; _enabled = true; _revision++;
        _settings.TargetHint = _target.Title; Save(); Update();
    }
    public void Pause() { _enabled = false; _revision++; UpdateConfiguration([]); }

    private void ConfirmCalibration()
    {
        var client = ClientBounds(_target!.Handle);
        _calibratedAspect = _settings.CalibratedAspect = client.Width / client.Height; _calibrated = true;
        _notice = ""; _pointNeedsReview = false;
        _targetStatus.Text = "스크롤 위치 준비됨 · 아래 ‘사용하기’를 누르세요.";
    }
    private void PrepareScrollPoint()
    {
        var client = ClientBounds(_target!.Handle);
        if (!CanReuseScrollPoint(_settings, _target, client))
        {
            _settings.VideoLeft = _settings.VideoTop = 0;
            _settings.VideoRight = _settings.VideoBottom = 1;
            _settings.U = _settings.V = .5;
        }
        ConfirmCalibration();
    }
    internal static bool CanReuseScrollPoint(RemoteSettings settings, MirrorTarget target, PixelRect client) =>
        settings.TargetHint == target.Title && settings.CalibratedAspect > 0 && client.Height > 0 &&
        Math.Abs(client.Width / client.Height / settings.CalibratedAspect - 1) <= .02;
    private void Calibrate()
    {
        Pause();
        if (_target is null || !Valid(_target)) { Notice("미러링 창을 먼저 선택하세요."); return; }
        var client = ClientBounds(_target.Handle);
        var overlay = new Window { Owner = _owner, Title = "영상 지점 지정", WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, Topmost = true, Background = new SolidColorBrush(Color.FromArgb(120, 12, 22, 35)), AllowsTransparency = true };
        var canvas = new Grid();
        var hint = new TextBlock { Text = "① 검은 여백을 제외한 영상 왼쪽 위를 클릭하세요.", FontSize = 16, Foreground = Brushes.White, Background = Brushes.Black, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Top, IsHitTestVisible = false, Margin = new Thickness(8, 55, 8, 0) };
        var cancel = new Button { Content = "지정 취소", Height = 48, Width = 130, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top };
        cancel.Click += (_, e) => { e.Handled = true; overlay.Close(); };
        canvas.Children.Add(hint); canvas.Children.Add(cancel); overlay.Content = canvas;
        var points = new List<System.Windows.Point>();
        overlay.PreviewMouseLeftButtonUp += (_, e) =>
        {
            if (cancel.IsMouseOver) return;
            e.Handled = true;
            if (!Valid(_target) || ClientBounds(_target.Handle) != client) { overlay.Close(); Notice("창이 이동/변경되어 지정을 취소했습니다."); return; }
            var p = overlay.PointToScreen(e.GetPosition(overlay));
            points.Add(new((p.X - client.X) / client.Width, (p.Y - client.Y) / client.Height));
            if (points.Count == 1) hint.Text = "② 영상 오른쪽 아래를 클릭하세요.";
            else if (points.Count == 2)
            {
                if (points[1].X - points[0].X < .05 || points[1].Y - points[0].Y < .05) { points.Clear(); hint.Text = "영역이 너무 작습니다. ① 영상 왼쪽 위를 다시 클릭하세요."; }
                else hint.Text = "③ 영상 안에서 스크롤할 지점을 클릭하세요.";
            }
            else
            {
                var a = points[0]; var b = points[1]; var p3 = points[2];
                if (p3.X < a.X || p3.X >= b.X || p3.Y < a.Y || p3.Y >= b.Y) { points.RemoveAt(2); hint.Text = "③ 지정한 영상 영역 안을 클릭하세요."; return; }
                _settings.VideoLeft = a.X; _settings.VideoTop = a.Y; _settings.VideoRight = b.X; _settings.VideoBottom = b.Y;
                _settings.U = (p3.X - a.X) / (b.X - a.X); _settings.V = (p3.Y - a.Y) / (b.Y - a.Y);
                ConfirmCalibration(); Save(); overlay.Close();
            }
        };
        overlay.Loaded += (_, _) => Place(new WindowInteropHelper(overlay).Handle, client);
        overlay.ShowDialog();
    }

    private void Update()
    {
        if (_disposed) return;
        var view = _relay.View;
        _runState.Text = _covered ? "휴대폰 창이 가려져 버튼을 숨겼습니다." : _enabled ? $"● 사용 중 · {(_settings.Activation == "dwell" ? $"{_settings.DwellMs / 1000.0:0.##}초 바라보면 실행" : "클릭하면 실행")}" : _target is null ? "먼저 휴대폰 창을 골라 주세요." : "Ⅱ 일시 정지 · ‘사용하기’를 누르면 버튼이 작동합니다.";
        _runState.Foreground = _enabled && !_covered ? Brushes.LightGreen : Brushes.LightSteelBlue;
        if (_covered) _pointer.Hide(); else _pointer.Update(view);
        _status.Text = _loadError.Length != 0 ? _loadError : _notice.Length != 0 ? _notice : _layoutMessage.Length != 0 ? _layoutMessage : view.Status;
        _noticeBanner.Text = _loadError.Length != 0 ? _loadError : _notice.Length != 0 ? _notice : _layoutMessage;
        _noticeBanner.Visibility = _noticeBanner.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        if (_notice.Length == 0 && _layoutMessage.Length == 0 && view.Completed > 0)
            _status.Text += $"\n최근 최대 50회 · 중앙 {view.MedianMs}ms · 최대 {view.MaxMs}ms";
        if (_target is null)
        {
            if (_visible) HideControls();
            return;
        }
        if (!_visible) return;
        try
        {
            if (!Valid(_target))
            {
                if (_enabled) Pause();
                foreach (var b in _buttons.Values) b.Hide();
                _layoutMessage = "대상 창이 닫혔거나 최소화되었습니다. 새 응시로 자동 재개하지 않습니다.";
                UpdateConfiguration(VisibleHits()); return;
            }
            var now = Environment.TickCount64;
            if (now >= _nextCoverCheck)
            {
                var ignored = _buttons.Values.Select(b => b.Handle).Append(_pointer.NativeHandle).ToArray();
                var covered = IsCovered(_target, ignored);
                _nextCoverCheck = now + 120;
                if (covered != _covered) { _covered = covered; _revision++; _toolbarUntil = 0; }
            }
            if (_covered)
            {
                foreach (var button in _buttons.Values) button.Hide();
                _pointer.Hide();
                _layoutMessage = "다른 창에 가려졌습니다. 휴대폰 창을 앞으로 가져오면 버튼이 다시 나타납니다.";
                UpdateConfiguration([]);
                return;
            }
            var window = WindowBounds(_target.Handle); var client = ClientBounds(_target.Handle);
            var scale = GetDpiForWindow(_target.Handle) / 96.0;
            var work = WorkArea(_target.Handle);
            var fitted = RemoteLayout.FitTarget(_settings, window, work, scale, window.Width - client.Width, window.Height - client.Height);
            if (fitted is { } fit && fit != window && !ButtonsHeld())
            {
                var resume = _enabled;
                Pause();
                if (!SetPosition(_target.Handle, 0, (int)fit.X, (int)fit.Y, (int)fit.Width, (int)fit.Height, 0x4 | 0x10))
                    throw new InvalidOperationException("휴대폰 창 위치를 조정하지 못했습니다.");
                window = WindowBounds(_target.Handle); client = ClientBounds(_target.Handle);
                // This resize preserves the video aspect, including window chrome.
                // It is our own fitting move, not an Android rotation.
                _calibratedAspect = _settings.CalibratedAspect = client.Width / client.Height;
                _enabled = resume && _calibrated;
            }
            if (window != _lastWindow || client != _lastClient)
            {
                _revision++; _lastWindow = window; _lastClient = client;
                if (_calibrated && Math.Abs(client.Width / client.Height / _calibratedAspect - 1) > .02)
                {
                    if (_settings.HasCustomPoint) { _calibrated = false; _pointNeedsReview = true; _enabled = false; _targetStatus.Text = "영상 비율이 바뀌었습니다. 고급 설정에서 위치를 다시 확인하세요."; }
                    else _calibratedAspect = _settings.CalibratedAspect = client.Width / client.Height;
                }
            }
            var positions = RemoteLayout.Calculate(_settings, window, scale);
            if (!RemoteLayout.Fits(positions, work))
            {
                _enabled = false;
                _layoutMessage = "이 화면에 현재 버튼 크기를 모두 놓을 수 없습니다. 버튼 크기나 배치를 바꿔 주세요.";
                foreach (var b in _buttons.Values.Where(b => b.Action is not RemoteAction.Stop and not RemoteAction.Settings)) b.Hide();
            }
            else
            {
                _layoutMessage = "";
                foreach (var p in positions) Button(p.Action).Position(p.Bounds);
            }
            PlaceUtilities(window, view, scale);
            foreach (var b in _buttons.Values) b.Paint(view, _enabled, _settings);
            UpdateConfiguration(VisibleHits());
        }
        catch (Exception ex) { _enabled = false; _layoutMessage = ex.Message; UpdateConfiguration([]); }
    }
    private RemoteButtonWindow Button(RemoteAction action)
    {
        if (!_buttons.TryGetValue(action, out var button)) _buttons[action] = button = new(action);
        return button;
    }
    private RemoteHit[] VisibleHits() => _buttons.Values.Where(b => b.IsVisible).Select(b => new RemoteHit(b.Action, b.Bounds, b.Handle)).ToArray();
    private void UpdateConfiguration(RemoteHit[] hits)
    {
        var client = _lastClient;
        var video = new PixelRect(client.X + client.Width * _settings.VideoLeft, client.Y + client.Height * _settings.VideoTop,
            client.Width * (_settings.VideoRight - _settings.VideoLeft), client.Height * (_settings.VideoBottom - _settings.VideoTop));
        // The worker receives an immutable settings snapshot; UI edits cannot mutate
        // a running excursion before its cancel/restore boundary.
        var copy = JsonSerializer.Deserialize<RemoteSettings>(JsonSerializer.Serialize(_settings))!;
        _relay.Configure(new(_target, copy, hits, client, video, _enabled && _calibrated && _owner.IsEnabled && !_covered, _revision));
    }
    private void PlaceUtilities(PixelRect window, RelayView view, double scale)
    {
        var p = view.Logical;
        var root = GetAncestor(WindowFromPoint(p), 2);
        var overPhone = _lastWindow.Contains(p.X, p.Y) && root == _target!.Handle;
        var overToolbar = _buttons.Values.Any(b => b.IsVisible && (b.Action is RemoteAction.Stop or RemoteAction.Settings) && b.Bounds.Contains(p.X, p.Y) && root == b.Handle);
        var now = Environment.TickCount64;
        if (overPhone || overToolbar) _toolbarUntil = now + 1200;
        var show = overPhone || overToolbar || now < _toolbarUntil;
        foreach (var placement in RemoteLayout.Utilities(_settings, window, scale))
        {
            var button = Button(placement.Action);
            if (show) button.Position(placement.Bounds);
            else button.Hide();
        }
    }
    private void FitTogether()
    {
        Pause(); if (_target is null || !Valid(_target)) return;
        var target = WindowBounds(_target.Handle); var client = ClientBounds(_target.Handle); var work = WorkArea(_target.Handle);
        var fit = RemoteLayout.FitTarget(_settings, target, work, GetDpiForWindow(_target.Handle) / 96.0,
            target.Width - client.Width, target.Height - client.Height);
        if (fit is not { } rect) { Notice("현재 버튼 크기를 이 화면에 모두 놓을 수 없습니다. 버튼 크기나 배치를 바꿔 주세요."); return; }
        if (!SetPosition(_target.Handle, 0, (int)rect.X, (int)rect.Y, (int)rect.Width, (int)rect.Height, 0x4 | 0x10)) { Notice("창 위치를 조정하지 못했습니다."); return; }
        _notice = "창 위치를 정리했습니다. ‘사용하기’를 누르면 버튼이 작동합니다.";
        _lastWindow = default; Update();
    }
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SetWindowPos")]
    private static extern bool SetPosition(nint hwnd, nint after, int x, int y, int width, int height, uint flags);

    public void Dispose()
    {
        if (_disposed) return; _disposed = true; _timer.Stop(); _owner.IsEnabledChanged -= OwnerEnabledChanged; _owner.StateChanged -= OwnerStateChanged; _relay.Dispose();
        foreach (var b in _buttons.Values) b.Close(); _pointer.Close();
    }
}
