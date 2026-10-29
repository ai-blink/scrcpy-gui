using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace ScrcpyGui;

internal static class ScrcpyCommandLine
{
    internal static string[] Parse(string text)
    {
        var quoted = false; var slashes = 0;
        foreach (var c in text)
        {
            if (c == '"' && slashes % 2 == 0) quoted = !quoted;
            slashes = c == '\\' ? slashes + 1 : 0;
        }
        if (quoted) throw new FormatException("직접 인자의 큰따옴표가 닫히지 않았습니다.");
        var pointer = CommandLineToArgvW("scrcpy.exe " + text.Replace('\r', ' ').Replace('\n', ' '), out var count);
        if (pointer == 0) throw new Win32Exception();
        try { return Enumerable.Range(1, count - 1).Select(i => Marshal.PtrToStringUni(Marshal.ReadIntPtr(pointer, i * IntPtr.Size)) ?? "").ToArray(); }
        finally { LocalFree(pointer); }
    }
    internal static string Quote(string argument)
    {
        if (argument.Length > 0 && !argument.Any(c => char.IsWhiteSpace(c) || c == '"')) return argument;
        var output = new StringBuilder("\""); var slashes = 0;
        foreach (var c in argument)
        {
            if (c == '\\') { slashes++; continue; }
            output.Append('\\', c == '"' ? slashes * 2 + 1 : slashes); output.Append(c); slashes = 0;
        }
        return output.Append('\\', slashes * 2).Append('"').ToString();
    }
    internal static bool CapturesPointer(IReadOnlyList<string> args)
    {
        string? mouse = null; var capture = false;
        for (var i = 0; i < args.Count; i++)
        {
            var arg = args[i]; if (arg == "--") break;
            if (arg.StartsWith("--"))
            {
                var split = arg.IndexOf('='); var name = split < 0 ? arg : arg[..split];
                var flag = name is "--otg" or "--relative-mouse";
                if (flag) capture = true;
                var value = split >= 0 ? arg[(split + 1)..] : name is "--mouse" or "--record" or "--window-title" or "--serial" or "--max-size" or "--video-bit-rate" or "--shortcut-mod" or "--start-app" or "--display-id" or "--port" or "--verbosity" ? i + 1 < args.Count ? args[++i] : null : null;
                if (name == "--mouse") mouse = value;
                continue;
            }
            if (arg.Length < 2 || arg[0] != '-') continue;
            for (var j = 1; j < arg.Length; j++)
            {
                if (arg[j] == 'M') capture = true;
                if ("bmprsV".Contains(arg[j])) { if (j == arg.Length - 1 && i + 1 < args.Count) i++; break; }
                if (!"defGhKMnNStvwx".Contains(arg[j])) break;
            }
        }
        return capture || mouse is "uhid" or "aoa";
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern nint CommandLineToArgvW(string command, out int count);
    [DllImport("kernel32.dll")] private static extern nint LocalFree(nint pointer);
}
