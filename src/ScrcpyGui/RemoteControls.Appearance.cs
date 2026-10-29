using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace ScrcpyGui;

internal sealed partial class RemoteControls
{
    private readonly RemoteButtonVisual _stylePreview = new() { Width = 120, Height = 90 };
    private readonly RemoteButtonVisual _appearancePreview = new() { Width = 120, Height = 90 };
    private StackPanel SettingsTab(string title)
    {
        var body = new StackPanel { Margin = new Thickness(4, 12, 4, 8) };
        _settingsTabs.Items.Add(new TabItem { Header = title, Content = body });
        return body;
    }
    private void BuildAppearanceTabs()
    {
        var appearance = SettingsTab("글자·색상");
        appearance.Children.Add(new TextBlock { Text = "전체 버튼에 적용됩니다. 색 이름을 고르거나 #RRGGBB 코드를 입력하세요.", TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightSlateGray, Margin = new Thickness(0, 0, 0, 12) });
        Number("글자 크기 (DIP)", _settings.FontSize, 8, 48, v => _settings.FontSize = v, appearance);
        ColorPicker(appearance, "글자 색", _settings.FontColor, v => _settings.FontColor = v);
        ColorPicker(appearance, "버튼 배경", _settings.BackgroundColor, v => _settings.BackgroundColor = v);
        ColorPicker(appearance, "버튼 테두리", _settings.BorderColor, v => _settings.BorderColor = v);
        Number("모서리 둥글기", _settings.CornerRadius, 0, 50, v => _settings.CornerRadius = v, appearance);
        Number("버튼 불투명도 (%)", _settings.ButtonOpacity, 25, 100, v => _settings.ButtonOpacity = v, appearance);
        appearance.Children.Add(new Border { Child = _appearancePreview, HorizontalAlignment = HorizontalAlignment.Center, Padding = new Thickness(12), Background = new SolidColorBrush(Color.FromRgb(12, 14, 18)), CornerRadius = new CornerRadius(12) });
        appearance.Children.Add(new TextBlock { Text = "버튼 미리보기 · 실제 입력 없음", TextAlignment = TextAlignment.Center, Foreground = Brushes.LightSlateGray });

        var feedback = SettingsTab("드웰 피드백");
        feedback.Children.Add(new TextBlock { Text = "게이지가 차오르면 실행합니다. 아래 미리보기는 휴대폰에 입력을 보내지 않습니다.", TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightSlateGray, Margin = new Thickness(0, 0, 0, 12) });
        var patterns = new[] { "bar", "ring", "fill", "none" };
        var mode = new ComboBox { ItemsSource = new[] { "아래쪽 막대", "테두리를 도는 링", "아래에서 위로 채우기", "게이지 숨기기" }, SelectedIndex = Array.IndexOf(patterns, _settings.GaugePattern), MinHeight = 44, Margin = new Thickness(0, 0, 0, 12) };
        mode.SelectionChanged += (_, _) => { if (mode.SelectedIndex >= 0) Change(() => _settings.GaugePattern = patterns[mode.SelectedIndex]); };
        feedback.Children.Add(mode);
        ColorPicker(feedback, "응시 게이지 색", _settings.GaugeColor, v => _settings.GaugeColor = v);
        Number("막대·링 두께", _settings.GaugeThickness, 2, 16, v => _settings.GaugeThickness = v, feedback);
        Check("실행 완료 시 배경색으로 알리기", _settings.CompletionFlash, v => _settings.CompletionFlash = v, feedback);
        ColorPicker(feedback, "실행 완료 색", _settings.CompletionColor, v => _settings.CompletionColor = v);
        Number("완료 표시 시간 (ms)", _settings.CompletionFlashMs, 0, 1000, v => _settings.CompletionFlashMs = v, feedback);
        feedback.Children.Add(new Border { Child = _stylePreview, HorizontalAlignment = HorizontalAlignment.Center, Padding = new Thickness(12), Margin = new Thickness(0, 8, 0, 8), Background = new SolidColorBrush(Color.FromRgb(12, 14, 18)), CornerRadius = new CornerRadius(12) });
        feedback.Children.Add(new TextBlock { Text = "자동 재생 미리보기 · 실제 입력 없음", TextAlignment = TextAlignment.Center, Foreground = Brushes.LightSlateGray });
    }
    private void ColorPicker(Panel parent, string label, string value, Action<string> apply)
    {
        var colors = new[] { ("흰색", "#FFFFFF"), ("검정", "#101010"), ("남색", "#18202E"), ("회색", "#708090"), ("하늘색", "#00BFFF"), ("파랑", "#387BFF"), ("초록", "#44D17A"), ("노랑", "#FFD75E"), ("주황", "#FF963C"), ("분홍", "#FF6FAD"), ("보라", "#B18CFF"), ("사용자 지정", value) };
        var row = new Grid { Margin = new Thickness(0, 5, 0, 9) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
        var controls = new StackPanel { Orientation = Orientation.Horizontal };
        var swatch = new Border { Width = 22, Height = 30, Background = RemoteButtonVisual.Brush(value), BorderBrush = Brushes.SlateGray, BorderThickness = new Thickness(1), Margin = new Thickness(0, 0, 8, 0) };
        var choice = new ComboBox { ItemsSource = colors.Select(c => c.Item1), SelectedIndex = Array.FindIndex(colors, c => c.Item2.Equals(value, StringComparison.OrdinalIgnoreCase)), Width = 110, MinHeight = 44, Margin = new Thickness(0, 0, 6, 0) };
        var hex = new TextBox { Text = value, Width = 96, MinHeight = 44, VerticalContentAlignment = VerticalAlignment.Center, ToolTip = "#RRGGBB · 예: #00BFFF" };
        System.Windows.Automation.AutomationProperties.SetName(hex, label + " 색상 코드");
        System.Windows.Automation.AutomationProperties.SetName(choice, label);
        var current = value;
        void SetColor(string color)
        {
            if (!RemoteSettings.IsColor(color)) { hex.Text = current; return; }
            color = color.ToUpperInvariant(); hex.Text = color; swatch.Background = RemoteButtonVisual.Brush(color);
            if (current == color) return;
            current = color; Change(() => apply(color));
        }
        choice.SelectionChanged += (_, _) => { if (choice.SelectedIndex >= 0 && choice.SelectedIndex < colors.Length - 1) SetColor(colors[choice.SelectedIndex].Item2); };
        hex.LostKeyboardFocus += (_, _) => { SetColor(hex.Text.Trim()); choice.SelectedIndex = Array.FindIndex(colors, c => c.Item2.Equals(current, StringComparison.OrdinalIgnoreCase)); if (choice.SelectedIndex < 0) choice.SelectedIndex = colors.Length - 1; };
        hex.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) { SetColor(hex.Text.Trim()); e.Handled = true; } };
        controls.Children.Add(swatch); controls.Children.Add(choice); controls.Children.Add(hex);
        Grid.SetColumn(controls, 1); row.Children.Add(controls); parent.Children.Add(row);
    }
    private void AnimateFeedbackPreview()
    {
        if (!_stylePreview.IsVisible && !_appearancePreview.IsVisible) return;
        var duration = Math.Max(200, _settings.DwellMs);
        var phase = Environment.TickCount64 % (duration + Math.Max(500, _settings.CompletionFlashMs));
        _stylePreview.Width = Math.Min(240, Math.Max(72, _settings.Size) * _settings.WidthPercent / 100.0);
        _stylePreview.Height = Math.Max(72, _settings.Size);
        _stylePreview.Paint(_settings, RemoteAction.Down, phase < duration ? (double)phase / duration : 0, true, true,
            _settings.CompletionFlash && phase >= duration && phase < duration + _settings.CompletionFlashMs);
        _appearancePreview.Width = _stylePreview.Width; _appearancePreview.Height = _stylePreview.Height;
        _appearancePreview.Paint(_settings, RemoteAction.Down, 0, false, true);
    }
}
