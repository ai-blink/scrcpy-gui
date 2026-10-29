using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace ScrcpyGui;

internal sealed record MirrorTarget(nint Handle, int Pid, long Started, string Title, string CommandLine, string Error, ushort[] Modifiers)
{
    public override string ToString() => Title;
}

internal static class RemoteNative
{
    internal static readonly nuint Tag = 0x53435247;
    internal const int Move = 0x200, LeftDown = 0x201, LeftUp = 0x202;
    internal delegate nint HookProc(int code, nint message, nint data);
    private delegate bool EnumProc(nint hwnd, nint param);
    [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X, Y; public Point(int x, int y) { X = x; Y = y; } }
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; public readonly PixelRect Pixels => new(Left, Top, Right - Left, Bottom - Top); }
    [StructLayout(LayoutKind.Sequential)] internal struct HookData { public Point Point; public uint MouseData, Flags, Time; public nuint Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct MouseInput { public int X, Y; public uint Data, Flags, Time; public nuint Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct KeyInput { public ushort Key, Scan; public uint Flags, Time; public nuint Extra; }
    [StructLayout(LayoutKind.Explicit)] private struct InputUnion { [FieldOffset(0)] public MouseInput Mouse; [FieldOffset(0)] public KeyInput Key; }
    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public InputUnion Union; }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
    [StructLayout(LayoutKind.Sequential)] private struct UnicodeString { public ushort Length, Maximum; public nint Buffer; }
    [StructLayout(LayoutKind.Sequential)] internal struct Message { public nint Hwnd; public uint Id; public nuint WParam; public nint LParam; public uint Time; public Point Point; public uint Private; }

    public static List<MirrorTarget> Enumerate()
    {
        var result = new List<MirrorTarget>();
        var cache = new Dictionary<int, (long Started, string Command)>();
        EnumWindows((h, _) =>
        {
            if (!IsWindowVisible(h) || GetWindow(h, 4) != 0) return true;
            GetWindowThreadProcessId(h, out var pid);
            try
            {
                using var p = Process.GetProcessById((int)pid);
                // WPF GUI and console windows cannot become input targets.
                if (!string.Equals(p.ProcessName, "scrcpy", StringComparison.OrdinalIgnoreCase)) return true;
                var cls = new StringBuilder(256); GetClassName(h, cls, cls.Capacity);
                if (!cls.ToString().StartsWith("SDL", StringComparison.Ordinal)) return true;
                var title = new StringBuilder(1024); GetWindowText(h, title, title.Capacity);
                if (!cache.TryGetValue((int)pid, out var meta))
                    cache[(int)pid] = meta = (p.StartTime.ToUniversalTime().Ticks, ReadCommandLine((int)pid));
                var (error, modifiers) = ParseOptions(meta.Command);
                result.Add(new(h, (int)pid, meta.Started, title.ToString(), meta.Command, error, modifiers));
            }
            catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException or ArgumentException) { }
            return true;
        }, 0);
        return result;
    }

    internal static string ReadCommandLine(int pid)
    {
        var process = OpenProcess(0x1000, false, pid);
        if (process == 0) return "";
        try
        {
            NtQueryInformationProcess(process, 60, 0, 0, out var length);
            if (length <= 0 || length > 1024 * 1024) return "";
            var buffer = Marshal.AllocHGlobal(length);
            try
            {
                if (NtQueryInformationProcess(process, 60, buffer, length, out _) != 0) return "";
                var value = Marshal.PtrToStructure<UnicodeString>(buffer);
                return Marshal.PtrToStringUni(value.Buffer, value.Length / 2) ?? "";
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        finally { CloseHandle(process); }
    }

    internal static (string Error, ushort[] Modifiers) ParseOptions(string command)
    {
        if (string.IsNullOrWhiteSpace(command)) return ("실행 옵션을 읽을 수 없습니다. 같은 권한의 scrcpy 창을 선택하세요.", []);
        var argv = CommandLineToArgvW(command, out var count);
        if (argv == 0) return ("실행 옵션을 해석하지 못했습니다.", []);
        string[] args;
        try { args = Enumerable.Range(1, Math.Max(0, count - 1)).Select(i => Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv, i * IntPtr.Size)) ?? "").ToArray(); }
        finally { LocalFree(argv); }
        string? mouse = null, modifier = null;
        var readOnly = false; var capture = false;
        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (arg == "--") break;
            if (arg.StartsWith("--", StringComparison.Ordinal))
            {
                var separator = arg.IndexOf('=');
                var name = separator < 0 ? arg : arg[..separator];
                var takesValue = name is "--mouse" or "--shortcut-mod" or "--serial" or "--record" or "--window-title"
                    or "--video-bit-rate" or "--max-size" or "--port" or "--verbosity";
                var argumentValue = separator >= 0 ? arg[(separator + 1)..] : takesValue && i + 1 < args.Length ? args[++i] : null;
                if (name == "--no-control") readOnly = true;
                if (name is "--otg" or "--relative-mouse") capture = true;
                if (name == "--mouse") mouse = argumentValue;
                if (name == "--shortcut-mod") modifier = argumentValue;
                continue;
            }
            if (arg.Length < 2 || arg[0] != '-') continue;
            // getopt accepts groups such as -fn and -fM. An option requiring a
            // value consumes the rest of the token (or the next token), so a
            // serial/file name containing n or M is never treated as a flag.
            for (var j = 1; j < arg.Length; j++)
            {
                var option = arg[j];
                if (option == 'n') readOnly = true;
                if (option == 'M') capture = true;
                if ("bmprsV".Contains(option)) { if (j == arg.Length - 1 && i + 1 < args.Length) i++; break; }
                if (!"defGhKMnNStvwx".Contains(option)) break;
            }
        }
        if (readOnly) return ("보기 전용 창은 조작할 수 없습니다.", []);
        if (mouse is "uhid" or "aoa" or "disabled" || capture)
            return ("캡처형/비활성 마우스 옵션입니다. sdk 마우스 창을 선택하세요.", []);
        var value = modifier ?? "lalt";
        var first = value.Split(',')[0];
        var keys = new List<ushort>();
        foreach (var part in first.Split('+'))
        {
            ushort key = part switch { "lalt" => 0xA4, "ralt" => 0xA5, "lctrl" => 0xA2, "rctrl" => 0xA3, "lsuper" => 0x5B, "rsuper" => 0x5C, _ => 0 };
            if (key == 0) return ($"지원하지 않는 단축키 보조키: {value}", []);
            keys.Add(key);
        }
        return ("", keys.Distinct().ToArray());
    }

    public static bool Valid(MirrorTarget target)
    {
        if (!IsWindow(target.Handle) || !IsWindowVisible(target.Handle) || IsIconic(target.Handle)) return false;
        GetWindowThreadProcessId(target.Handle, out var pid);
        if (pid != target.Pid) return false;
        try { using var p = Process.GetProcessById(target.Pid); return p.StartTime.ToUniversalTime().Ticks == target.Started && GetWindow(target.Handle, 6) == 0; }
        catch { return false; }
    }
    public static PixelRect WindowBounds(nint h) => GetWindowRect(h, out var r) ? r.Pixels : throw new InvalidOperationException("창 위치 읽기 실패");
    public static PixelRect ClientBounds(nint h)
    {
        if (!GetClientRect(h, out var r)) throw new InvalidOperationException("영상 영역 읽기 실패");
        var p = new Point(0, 0);
        if (!ClientToScreen(h, ref p) || r.Right < 1 || r.Bottom < 1) throw new InvalidOperationException("영상 영역이 비어 있습니다.");
        return new(p.X, p.Y, r.Right, r.Bottom);
    }
    public static PixelRect WorkArea(nint h)
    {
        var m = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(MonitorFromWindow(h, 2), ref m)) throw new InvalidOperationException("모니터 영역 읽기 실패");
        return m.Work.Pixels;
    }
    public static bool AtTarget(MirrorTarget t, Point point) => Valid(t) && GetAncestor(WindowFromPoint(point), 2) == t.Handle;
    public static bool IsCovered(MirrorTarget target, IReadOnlyCollection<nint> ignored)
    {
        // A foreground mirror must remain usable beneath assistive topmost surfaces.
        if (GetForegroundWindow() == target.Handle) return false;
        var client = ClientBounds(target.Handle);
        var covered = false;
        // EnumWindows walks Z order: only windows above this mirror can cover it.
        EnumWindows((window, _) =>
        {
            if (window == target.Handle) return false;
            if (ignored.Contains(window) || !IsWindowVisible(window) || IsIconic(window) || !GetWindowRect(window, out var bounds)) return true;
            if (IsAssistiveSurface((long)GetWindowLongPtr(window, -20))) return true;
            covered = CoversIntersection(client, bounds.Pixels, target.Handle, ignored,
                p =>
                {
                    var root = GetAncestor(WindowFromPoint(p), 2);
                    return root != 0 && IsAssistiveSurface((long)GetWindowLongPtr(root, -20)) ? 0 : root;
                });
            return !covered;
        }, 0);
        return covered;
    }
    internal static bool IsAssistiveSurface(long extendedStyle) => (extendedStyle & (0x08000000L | 0x20L)) != 0;
    internal static bool CoversIntersection(PixelRect target, PixelRect cover, nint targetWindow,
        IReadOnlyCollection<nint> ignored, Func<Point, nint> windowAt)
    {
        var left = Math.Max(target.X, cover.X); var top = Math.Max(target.Y, cover.Y);
        var right = Math.Min(target.Right, cover.Right); var bottom = Math.Min(target.Bottom, cover.Bottom);
        if (right <= left || bottom <= top) return false;
        // Check the actual hit-test surface, not just a rectangular transparent
        // accessibility overlay. Our cursor marker and controls never count.
        foreach (var x in new[] { left, (left + right - 1) / 2, right - 1 })
        foreach (var y in new[] { top, (top + bottom - 1) / 2, bottom - 1 })
        {
            var root = windowAt(new((int)Math.Round(x), (int)Math.Round(y)));
            if (root != 0 && root != targetWindow && !ignored.Contains(root)) return true;
        }
        return false;
    }
    public static void Focus(MirrorTarget t)
    {
        if (!Valid(t) || !IsWindowEnabled(t.Handle)) throw new InvalidOperationException("대상 창이 닫혔거나 최소화/대화상자 상태입니다.");
        if (GetForegroundWindow() != t.Handle) SetForegroundWindow(t.Handle);
        if (GetForegroundWindow() != t.Handle) throw new InvalidOperationException("미러링 창 포커스를 확보하지 못했습니다. 입력을 중지했습니다.");
    }
    public static bool ModifiersHeld() => new[] { 0x10, 0x11, 0x12, 0x5B, 0x5C }.Any(k => (GetAsyncKeyState(k) & 0x8000) != 0);
    public static void Shortcut(MirrorTarget t, RemoteAction action)
    {
        if (ModifiersHeld()) throw new InvalidOperationException("사용자 보조키가 눌려 있습니다. 해제 후 다시 선택하세요.");
        Focus(t);
        var held = new List<ushort>();
        ushort key = action switch { RemoteAction.Back => 0x42, RemoteAction.Home => 0x48, RemoteAction.Recent => 0x53, _ => throw new ArgumentOutOfRangeException(nameof(action)) };
        try
        {
            foreach (var mod in t.Modifiers)
            {
                if (GetForegroundWindow() != t.Handle) throw new InvalidOperationException("입력 전 포커스가 변경되었습니다.");
                Key(mod, false); held.Add(mod);
            }
            if (GetForegroundWindow() != t.Handle) throw new InvalidOperationException("입력 전 포커스가 변경되었습니다.");
            Key(key, false); held.Add(key);
        }
        finally
        {
            Exception? releaseError = null;
            foreach (var k in held.AsEnumerable().Reverse())
            {
                try { Key(k, true); }
                catch (Exception ex) { releaseError ??= ex; }
            }
            if (releaseError is not null) throw new InvalidOperationException("키 해제를 완료하지 못했습니다.", releaseError);
        }
    }
    private static void Key(ushort key, bool up) => Send(new() { Type = 1, Union = new() { Key = new() { Key = key, Flags = (up ? 2u : 0) | (key is 0xA3 or 0xA5 or 0x5B or 0x5C ? 1u : 0), Extra = Tag } } });
    public static void MoveTo(Point p)
    {
        Send(AbsoluteMove(p));
    }
    private static Input AbsoluteMove(Point p) => new() { Union = new() { Mouse = new() {
        X = Normalize(p.X, GetSystemMetrics(76), GetSystemMetrics(78)),
        Y = Normalize(p.Y, GetSystemMetrics(77), GetSystemMetrics(79)), Flags = 0xC001, Extra = Tag } } };
    public static void WheelPulse(Point destination, int amount, Point restore)
    {
        // Same ordered SendInput batch as new-alt's AbsoluteWheelPulse.
        var inputs = CreateWheelPulse(destination, amount, restore);
        if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) != inputs.Length)
        {
            MoveTo(restore); // a partial submission must not strand the real cursor
            throw new InvalidOperationException("Windows가 스크롤 왕복 입력을 모두 수락하지 않았습니다.");
        }
    }
    private static Input[] CreateWheelPulse(Point destination, int amount, Point restore) =>
        [AbsoluteMove(destination), new() { Union = new() { Mouse = new() {
            Data = unchecked((uint)amount), Flags = 0x800, Extra = Tag } } }, AbsoluteMove(restore)];
    private static int Normalize(int p, int origin, int size) => (int)Math.Clamp(((long)p - origin) * 65535 / Math.Max(size - 1, 1), 0, 65535);
    public static void Wheel(int amount) => Send(new() { Union = new() { Mouse = new() { Data = unchecked((uint)amount), Flags = 0x800, Extra = Tag } } });
    public static bool ButtonsHeld() => new[] { 1, 2, 4, 5, 6 }.Any(k => (GetAsyncKeyState(k) & 0x8000) != 0);
    private static void Send(Input value)
    {
        if (SendInput(1, [value], Marshal.SizeOf<Input>()) != 1) throw new InvalidOperationException("Windows가 입력을 수락하지 않았습니다. 권한과 대상 상태를 확인하세요.");
    }
    public static void Place(nint h, PixelRect r) => SetWindowPos(h, -1, (int)Math.Round(r.X), (int)Math.Round(r.Y), (int)Math.Round(r.Width), (int)Math.Round(r.Height), 0x10 | 0x40);
    public static void NoActivate(nint h) => SetWindowLongPtr(h, -20, GetWindowLongPtr(h, -20) | 0x08000000 | 0x80);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, nint param);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(nint hwnd, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(nint hwnd, StringBuilder text, int count);
    [DllImport("kernel32.dll")] private static extern nint OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(nint handle);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern nint CommandLineToArgvW(string command, out int count);
    [DllImport("kernel32.dll")] private static extern nint LocalFree(nint handle);
    [DllImport("ntdll.dll")] private static extern int NtQueryInformationProcess(nint process, int info, nint buffer, int length, out int returned);
    [DllImport("user32.dll")] internal static extern bool IsWindow(nint hwnd);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint hwnd);
    [DllImport("user32.dll")] private static extern bool IsWindowEnabled(nint hwnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(nint hwnd);
    [DllImport("user32.dll")] private static extern nint GetWindow(nint hwnd, uint command);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint hwnd, out uint pid);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint hwnd, out Rect rect);
    [DllImport("user32.dll")] private static extern bool GetClientRect(nint hwnd, out Rect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(nint hwnd, ref Point point);
    [DllImport("user32.dll")] private static extern nint MonitorFromWindow(nint hwnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(nint hwnd);
    [DllImport("user32.dll")] internal static extern nint WindowFromPoint(Point point);
    [DllImport("user32.dll")] internal static extern nint GetAncestor(nint hwnd, uint flags);
    [DllImport("user32.dll")] internal static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint hwnd);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] internal static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern uint SendInput(uint count, Input[] input, int size);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(nint hwnd, nint after, int x, int y, int w, int h, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern nint GetWindowLongPtr(nint hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern nint SetWindowLongPtr(nint hwnd, int index, nint value);
    [DllImport("user32.dll")] internal static extern nint SetWindowsHookEx(int id, HookProc callback, nint module, uint thread);
    [DllImport("user32.dll")] internal static extern bool UnhookWindowsHookEx(nint hook);
    [DllImport("user32.dll")] internal static extern nint CallNextHookEx(nint hook, int code, nint message, nint data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] internal static extern nint GetModuleHandle(string? module);
    [DllImport("kernel32.dll")] internal static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] internal static extern int GetMessage(out Message message, nint hwnd, uint min, uint max);
    [DllImport("user32.dll")] internal static extern bool PeekMessage(out Message message, nint hwnd, uint min, uint max, uint remove);
    [DllImport("user32.dll")] internal static extern bool PostThreadMessage(uint thread, uint message, nuint w, nint l);
    [DllImport("user32.dll")] internal static extern nuint SetTimer(nint hwnd, nuint id, uint ms, nint proc);
    [DllImport("user32.dll")] internal static extern bool KillTimer(nint hwnd, nuint id);
}
