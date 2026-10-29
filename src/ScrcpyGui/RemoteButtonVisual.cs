using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace ScrcpyGui;

// Shared by the native overlay and the settings preview, so their feedback matches.
internal sealed class RemoteButtonVisual : Grid
{
    private readonly Border _surface = new();
    private readonly Border _fill = new() { VerticalAlignment = VerticalAlignment.Bottom };
    private readonly Border _bar = new() { HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Bottom };
    private readonly Path _ring = new() { IsHitTestVisible = false };
    private readonly TextBlock _caption = new() { TextAlignment = TextAlignment.Center, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(3) };
    private RemoteSettings _settings = new();
    private double _progress;
    public RemoteButtonVisual()
    {
        ClipToBounds = true;
        Children.Add(_surface); Children.Add(_fill); Children.Add(_caption); Children.Add(_bar); Children.Add(_ring);
        SizeChanged += (_, _) => DrawGauge();
    }
    internal static SolidColorBrush Brush(string hex) => new((Color)ColorConverter.ConvertFromString(hex));
    public void Paint(RemoteSettings settings, RemoteAction action, double progress, bool hover, bool enabled, bool flash = false)
    {
        _settings = settings; _progress = Math.Clamp(progress, 0, 1);
        Opacity = settings.ButtonOpacity / 100.0;
        _surface.CornerRadius = new CornerRadius(settings.CornerRadius);
        _surface.Background = Brush(flash ? settings.CompletionColor : settings.BackgroundColor);
        _surface.BorderBrush = Brush(hover ? settings.GaugeColor : settings.BorderColor);
        _surface.BorderThickness = new Thickness(hover ? 2 : 1);
        _caption.Foreground = Brush(settings.FontColor); _caption.FontSize = settings.FontSize;
        _caption.Text = action == RemoteAction.Stop ? enabled ? "Ⅱ\n일시 정지" : "▶\n사용 시작" : RemoteButtonWindow.Glyph(action) + "\n" + RemoteButtonWindow.Label(action);
        _caption.Opacity = enabled || action is RemoteAction.Stop or RemoteAction.Settings ? 1 : .45;
        _fill.Background = Brush(settings.GaugeColor); _fill.Opacity = .35;
        _bar.Background = Brush(settings.GaugeColor); _ring.Stroke = Brush(settings.GaugeColor);
        DrawGauge();
    }
    private void DrawGauge()
    {
        var width = ActualWidth; var height = ActualHeight;
        Clip = new RectangleGeometry(new Rect(0, 0, width, height), _settings.CornerRadius, _settings.CornerRadius);
        _bar.Visibility = _settings.GaugePattern == "bar" ? Visibility.Visible : Visibility.Collapsed;
        _fill.Visibility = _settings.GaugePattern == "fill" ? Visibility.Visible : Visibility.Collapsed;
        _ring.Visibility = _settings.GaugePattern == "ring" ? Visibility.Visible : Visibility.Collapsed;
        _bar.Width = width * _progress; _bar.Height = _settings.GaugeThickness;
        _fill.Height = height * _progress;
        _ring.StrokeThickness = _settings.GaugeThickness;
        var inset = _settings.GaugeThickness / 2.0 + 2;
        var rx = Math.Max(0, width / 2 - inset); var ry = Math.Max(0, height / 2 - inset);
        if (_progress <= 0 || rx == 0 || ry == 0) { _ring.Data = null; return; }
        var center = new Point(width / 2, height / 2);
        if (_progress >= 1) { _ring.Data = new EllipseGeometry(center, rx, ry); return; }
        var angle = 2 * Math.PI * _progress;
        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
        {
            context.BeginFigure(new(center.X, center.Y - ry), false, false);
            context.ArcTo(new(center.X + rx * Math.Sin(angle), center.Y - ry * Math.Cos(angle)), new Size(rx, ry), 0, _progress > .5, SweepDirection.Clockwise, true, false);
        }
        geometry.Freeze(); _ring.Data = geometry;
    }
}
