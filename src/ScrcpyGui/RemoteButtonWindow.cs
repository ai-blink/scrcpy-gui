using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using static ScrcpyGui.RemoteNative;

namespace ScrcpyGui;

internal sealed class RemoteButtonWindow : Window
{
    private readonly RemoteButtonVisual _visual = new();
    private int _completed = -1;
    private long _flashUntil;
    public RemoteAction Action { get; }
    public nint Handle { get; private set; }
    public PixelRect Bounds { get; private set; }
    public RemoteButtonWindow(RemoteAction action)
    {
        Action = action;
        Title = "휴대폰 조작판 · " + Label(action);
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false; ShowActivated = false; Topmost = true;
        Background = Brushes.Transparent; AllowsTransparency = true;
        Width = Height = 72;
        Content = _visual;
        SourceInitialized += (_, _) =>
        {
            Handle = new WindowInteropHelper(this).Handle;
            NoActivate(Handle);
            HwndSource.FromHwnd(Handle)?.AddHook((nint h, int msg, nint w, nint l, ref bool handled) =>
            {
                if (msg == 0x21) { handled = true; return 3; } // MA_NOACTIVATE
                // The low-level relay owns press/release. Native windows remain
                // opaque hit targets even when disconnected: no click-through.
                return 0;
            });
        };
    }
    public void Position(PixelRect bounds)
    {
        Bounds = bounds;
        if (!IsVisible) Show();
        Place(Handle, bounds);
    }
    public void Paint(RelayView view, bool enabled, RemoteSettings settings)
    {
        var hover = view.Hover == Action;
        if (_completed >= 0 && view.Completed > _completed && hover && settings.CompletionFlash) _flashUntil = Environment.TickCount64 + settings.CompletionFlashMs;
        _completed = view.Completed;
        _visual.Paint(settings, Action, hover ? view.Progress : 0, hover, enabled, settings.CompletionFlash && Environment.TickCount64 < _flashUntil);
    }
    internal static string Label(RemoteAction action) => action switch
    { RemoteAction.Back => "뒤로", RemoteAction.Home => "홈", RemoteAction.Recent => "최근 앱", RemoteAction.Up => "이전 내용", RemoteAction.Down => "다음 내용", RemoteAction.Stop => "정지", _ => "설정" };
    internal static string Glyph(RemoteAction action) => action switch
    { RemoteAction.Back => "↶", RemoteAction.Home => "⌂", RemoteAction.Recent => "▣", RemoteAction.Up => "▲", RemoteAction.Down => "▼", RemoteAction.Stop => "■", _ => "⚙" };
}

// Visual only. It cannot steal clicks or focus from the real desktop.
internal sealed class LogicalPointerWindow : Window
{
    private nint _handle;
    internal nint NativeHandle => _handle;
    public LogicalPointerWindow()
    {
        Title = "논리 포인터"; Width = Height = 24; WindowStyle = WindowStyle.None;
        AllowsTransparency = true; Background = Brushes.Transparent;
        ShowActivated = false; ShowInTaskbar = false; Topmost = true; IsHitTestVisible = false;
        Content = new Ellipse { Stroke = Brushes.DeepSkyBlue, StrokeThickness = 3, Fill = new SolidColorBrush(Color.FromArgb(70, 60, 180, 255)), Margin = new Thickness(2) };
        SourceInitialized += (_, _) =>
        {
            _handle = new WindowInteropHelper(this).Handle;
            NoActivate(_handle);
            // WS_EX_TRANSPARENT makes native hit testing pass through this visual.
            SetTransparent(_handle);
        };
    }
    public void Update(RelayView view)
    {
        if (!view.Busy) { Hide(); return; }
        if (!IsVisible) Show();
        Place(_handle, new(view.Logical.X - 12, view.Logical.Y - 12, 24, 24));
    }
    private static void SetTransparent(nint h) => SetWindowLongPtr(h, -20, GetWindowLongPtr(h, -20) | 0x20);
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern nint GetWindowLongPtr(nint h, int index);
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern nint SetWindowLongPtr(nint h, int index, nint value);
}
