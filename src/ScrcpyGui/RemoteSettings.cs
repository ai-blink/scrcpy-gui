using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ScrcpyGui;

internal enum RemoteAction { Back, Home, Recent, Up, Down, Stop, Settings }
internal sealed class LayoutChoice
{
    public string Side { get; set; } = "right";
    public string Align { get; set; } = "center";
    public string ScrollPosition { get; set; } = "bottom";
}

internal sealed class RemoteSettings
{
    public int Version { get; set; } = 1;
    public string Layout { get; set; } = "split";
    public LayoutChoice Split { get; set; } = new();
    public LayoutChoice Combined { get; set; } = new();
    [JsonIgnore] public LayoutChoice Choice => Layout == "combined" ? Combined : Split;
    public int Size { get; set; } = 72;
    public int Gap { get; set; } = 12;
    public int Distance { get; set; } = 20;
    public int GroupGap { get; set; } = 24;
    public string SizeMode { get; set; } = "fixed";
    public int RelativeSizePercent { get; set; } = 18;
    public int WidthPercent { get; set; } = 100;
    public int FontSize { get; set; } = 14;
    public string FontColor { get; set; } = "#FFFFFF";
    public string BackgroundColor { get; set; } = "#18202E";
    public string BorderColor { get; set; } = "#708090";
    public string GaugeColor { get; set; } = "#00BFFF";
    public string CompletionColor { get; set; } = "#44D17A";
    public string GaugePattern { get; set; } = "bar";
    public int GaugeThickness { get; set; } = 5;
    public int CornerRadius { get; set; } = 12;
    public int ButtonOpacity { get; set; } = 100;
    public bool CompletionFlash { get; set; } = true;
    public int CompletionFlashMs { get; set; } = 180;
    public string Activation { get; set; } = "dwell";
    public bool Repeat { get; set; } = true;
    public bool HoldRepeat { get; set; }
    public int DwellMs { get; set; } = 300;
    public int RepeatMs { get; set; } = 300;
    public string ScrollMode { get; set; } = "atomic";
    public int SettleMs { get; set; } = 20;
    public int Notches { get; set; } = 1;
    public int ArrivalMs { get; set; } = 60;
    public int AfterMs { get; set; } = 60;
    public bool BringForward { get; set; }
    public double U { get; set; } = .5;
    public double V { get; set; } = .5;
    // Display-oriented video bounds. Explicit calibration excludes letterboxing and
    // avoids inferring the Android aspect ratio from the resizable SDL client.
    public double VideoLeft { get; set; }
    public double VideoTop { get; set; }
    public double VideoRight { get; set; } = 1;
    public double VideoBottom { get; set; } = 1;
    public string TargetHint { get; set; } = "";
    public double CalibratedAspect { get; set; }
    [JsonIgnore] public bool HasCustomPoint => U != .5 || V != .5 || VideoLeft != 0 || VideoTop != 0 || VideoRight != 1 || VideoBottom != 1;

    public void Normalize()
    {
        Split ??= new(); Combined ??= new();
        Layout = Layout == "combined" ? "combined" : "split";
        foreach (var c in new[] { Split, Combined })
        {
            c.Side = c.Side == "left" ? "left" : "right";
            c.Align = c.Align is "top" or "bottom" ? c.Align : "center";
            c.ScrollPosition = c.ScrollPosition == "top" ? "top" : "bottom";
        }
        Size = Math.Clamp(Size, 32, 200); Gap = Math.Clamp(Gap, 0, 80);
        Distance = Math.Clamp(Distance, 0, 160); GroupGap = Math.Clamp(GroupGap, 0, 120);
        SizeMode = SizeMode == "relative" ? "relative" : "fixed";
        RelativeSizePercent = Math.Clamp(RelativeSizePercent, 5, 50); WidthPercent = Math.Clamp(WidthPercent, 50, 250);
        FontSize = Math.Clamp(FontSize, 8, 48); GaugeThickness = Math.Clamp(GaugeThickness, 2, 16);
        CornerRadius = Math.Clamp(CornerRadius, 0, 50); ButtonOpacity = Math.Clamp(ButtonOpacity, 25, 100);
        CompletionFlashMs = Math.Clamp(CompletionFlashMs, 0, 1000);
        GaugePattern = GaugePattern is "ring" or "fill" or "none" ? GaugePattern : "bar";
        FontColor = ColorOrDefault(FontColor, "#FFFFFF"); BackgroundColor = ColorOrDefault(BackgroundColor, "#18202E");
        BorderColor = ColorOrDefault(BorderColor, "#708090"); GaugeColor = ColorOrDefault(GaugeColor, "#00BFFF");
        CompletionColor = ColorOrDefault(CompletionColor, "#44D17A");
        DwellMs = Math.Clamp(DwellMs, 0, 3000); RepeatMs = Math.Clamp(RepeatMs, 0, 3000);
        ScrollMode = ScrollMode == "staged" ? "staged" : "atomic";
        SettleMs = Math.Clamp(SettleMs, 0, 500);
        Notches = Math.Clamp(Notches, 1, 10); ArrivalMs = Math.Clamp(ArrivalMs, 0, 500);
        AfterMs = Math.Clamp(AfterMs, 0, 500);
        Activation = Activation == "click" ? "click" : "dwell";
        U = Finite(U, .5); V = Finite(V, .5);
        VideoLeft = Finite(VideoLeft, 0); VideoTop = Finite(VideoTop, 0);
        VideoRight = Finite(VideoRight, 1); VideoBottom = Finite(VideoBottom, 1);
        if (VideoRight - VideoLeft < .05 || VideoBottom - VideoTop < .05)
        { VideoLeft = VideoTop = 0; VideoRight = VideoBottom = 1; }
    }
    private static double Finite(double value, double fallback) => double.IsFinite(value) ? Math.Clamp(value, 0, 1) : fallback;
    internal static bool IsColor(string? value) => value is { Length: 7 } && value[0] == '#' && uint.TryParse(value.AsSpan(1), System.Globalization.NumberStyles.HexNumber, null, out _);
    private static string ColorOrDefault(string? value, string fallback) => IsColor(value) ? value!.ToUpperInvariant() : fallback;

    public static RemoteSettings Load(string path)
    {
        if (!File.Exists(path)) return new();
        var json = File.ReadAllText(path);
        var value = JsonSerializer.Deserialize<RemoteSettings>(json)
            ?? throw new InvalidDataException("조작판 설정을 읽을 수 없습니다.");
        if (value.Version != 1) throw new InvalidDataException("지원하지 않는 조작판 설정 버전입니다.");
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty(nameof(ScrollMode), out _))
        {
            // Upgrade the old stock timings; retain individually tuned values.
            if (value.DwellMs == 700) value.DwellMs = 300;
            if (value.RepeatMs == 450) value.RepeatMs = 300;
        }
        value.Normalize(); return value;
    }
    public void Save(string path)
    {
        Normalize();
        if (File.Exists(path) && !File.Exists(path + ".bak")) File.Copy(path, path + ".bak");
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(path + ".tmp", path, true);
    }
}

internal readonly record struct PixelRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public bool Contains(double x, double y) => x >= X && y >= Y && x < Right && y < Bottom;
}
internal readonly record struct RemotePlacement(RemoteAction Action, PixelRect Bounds);

internal static class RemoteLayout
{
    public static (double Width, double Height) ButtonSize(RemoteSettings settings, PixelRect window, double scale)
    {
        var height = settings.SizeMode == "relative" ? Math.Clamp(window.Width * settings.RelativeSizePercent / 100, 32 * scale, 200 * scale) : settings.Size * scale;
        return (height * settings.WidthPercent / 100, height);
    }
    public static RemotePlacement[] Utilities(RemoteSettings settings, PixelRect window, double scale)
    {
        var (width, height) = ButtonSize(settings, window, scale);
        var gap = settings.Gap * scale;
        var x = window.X; var y = window.Y - height - settings.Distance * scale;
        return [new(RemoteAction.Stop, new(x, y, width, height)),
            new(RemoteAction.Settings, new(x + width + gap, y, width, height))];
    }
    public static PixelRect? FitTarget(RemoteSettings settings, PixelRect target, PixelRect work, double scale, double chromeWidth = 0, double chromeHeight = 0)
    {
        var current = target;
        for (var attempt = 0; attempt < 8; attempt++)
        {
            var all = Calculate(settings, current, scale).Concat(Utilities(settings, current, scale)).Select(p => p.Bounds).Append(current).ToArray();
            var left = all.Min(r => r.X); var right = all.Max(r => r.Right);
            var top = all.Min(r => r.Y); var bottom = all.Max(r => r.Bottom);
            var minX = Math.Ceiling(work.X - (left - current.X));
            var maxX = Math.Floor(work.Right - (right - current.X));
            var minY = Math.Ceiling(work.Y - (top - current.Y));
            var maxY = Math.Floor(work.Bottom - (bottom - current.Y));
            if (minX <= maxX && minY <= maxY)
                return current with { X = Math.Clamp(Math.Round(current.X), minX, maxX), Y = Math.Clamp(Math.Round(current.Y), minY, maxY) };
            var cw = current.Width - chromeWidth; var ch = current.Height - chromeHeight;
            if (cw <= 0 || ch <= 0) return null;
            var factor = Math.Min(1, Math.Min((cw - Math.Max(0, right - left - work.Width) - 2) / cw,
                (ch - Math.Max(0, bottom - top - work.Height) - 2) / ch));
            var width = Math.Floor(cw * factor); var height = Math.Floor(ch * factor);
            if (width < 80 * scale || height < 80 * scale) return null;
            current = current with { Width = width + chromeWidth, Height = height + chromeHeight };
        }
        return null;
    }
    public static (int X, int Y) ScrollPoint(PixelRect video, double u, double v)
    {
        if (video.Width < 1 || video.Height < 1) throw new InvalidOperationException("영상 영역이 비어 있습니다.");
        return ((int)Math.Clamp(Math.Round(video.X + video.Width * u), Math.Ceiling(video.X), Math.Ceiling(video.Right) - 1),
            (int)Math.Clamp(Math.Round(video.Y + video.Height * v), Math.Ceiling(video.Y), Math.Ceiling(video.Bottom) - 1));
    }
    // All geometry here is physical pixels; settings enter through the target DPI.
    public static List<RemotePlacement> Calculate(RemoteSettings s, PixelRect target, double scale)
    {
        var result = new List<RemotePlacement>();
        var (width, buttonHeight) = ButtonSize(s, target, scale); var gap = s.Gap * scale; var distance = s.Distance * scale;
        var nav = new[] { RemoteAction.Back, RemoteAction.Home, RemoteAction.Recent };
        var scroll = new[] { RemoteAction.Up, RemoteAction.Down };
        var combined = s.Layout == "combined";
        var order = combined ? (s.Choice.ScrollPosition == "top" ? scroll.Concat(nav) : nav.Concat(scroll)).ToArray() : scroll;
        var height = order.Length * buttonHeight + (combined ? 3 * gap + s.GroupGap * scale : gap);
        var x = s.Choice.Side == "left" ? target.X - distance - width : target.Right + distance;
        var y = s.Choice.Align switch { "top" => target.Y, "bottom" => target.Bottom - height, _ => target.Y + (target.Height - height) / 2 };
        for (var i = 0; i < order.Length; i++)
        {
            result.Add(new(order[i], new(x, y, width, buttonHeight)));
            var boundary = combined && i == (s.Choice.ScrollPosition == "top" ? 1 : 2);
            y += buttonHeight + (boundary ? s.GroupGap * scale : gap);
        }
        if (!combined)
        {
            x = target.X + (target.Width - (3 * width + 2 * gap)) / 2;
            for (var i = 0; i < nav.Length; i++) result.Add(new(nav[i], new(x + i * (width + gap), target.Bottom + distance, width, buttonHeight)));
        }
        return result;
    }

    public static bool Fits(IEnumerable<RemotePlacement> buttons, PixelRect work) => buttons.All(b =>
        b.Bounds.X >= work.X && b.Bounds.Y >= work.Y && b.Bounds.Right <= work.Right && b.Bounds.Bottom <= work.Bottom);
}
