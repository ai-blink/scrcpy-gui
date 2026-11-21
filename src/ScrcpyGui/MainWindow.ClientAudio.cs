using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows.Controls;

namespace ScrcpyGui;

// PC 마이크 → 폰 주입(scrcpy PR #7004의 --client-audio-source).
// 공식 scrcpy에는 없는 옵션이라, 이 옵션을 쓸 때만 C:\app\scrcpy-mic* 의 수정판 scrcpy로 실행한다.
public partial class MainWindow
{
    private string? _micScrcpyPath;

    private void ResolveMicScrcpy() => _micScrcpyPath =
        FirstExisting(Path.Combine(_dataDirectory, "scrcpy-mic", "scrcpy.exe"))
        ?? FindMatchingFiles(@"C:\app", "scrcpy-mic*", "scrcpy.exe").FirstOrDefault();

    private static bool UsesClientAudio(IEnumerable<string> arguments) =>
        arguments.Any(argument => argument.StartsWith("--client-audio-source", StringComparison.Ordinal));

    // 수정판 scrcpy에 PC 녹음 장치 목록을 물어 "audio=장치 이름" 항목으로 채운다.
    private async Task LoadClientAudioSourcesAsync()
    {
        ResolveMicScrcpy();
        if (!_controls.TryGetValue("client-audio-source", out var control) || control is not ComboBox combo) return;
        if (_micScrcpyPath is null)
        {
            combo.ToolTip = "마이크 전달 기능이 든 수정판 scrcpy(C:\\app\\scrcpy-mic*)를 찾지 못했습니다.";
            return;
        }
        var result = await RunProcessAsync(_micScrcpyPath, ["--list-client-audio-sources"], _lifetime.Token, TimeSpan.FromSeconds(10));
        var names = Regex.Matches(result.Output, @"^\s*@device\S+\s+\((?<name>.+)\)\s*$", RegexOptions.Multiline)
            .Select(match => "audio=" + match.Groups["name"].Value.Trim())
            .Distinct(StringComparer.Ordinal)
            .OrderBy(name => name, StringComparer.CurrentCulture);
        var current = combo.Text;
        _updating = true;
        try
        {
            foreach (var name in names)
                if (!combo.Items.Contains(name)) combo.Items.Add(name);
            combo.Text = current;
        }
        finally { _updating = false; }
    }
}
