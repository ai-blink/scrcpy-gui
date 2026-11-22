using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Windows;

namespace ScrcpyGui;

// 공식 scrcpy(adb 동봉) 설치 — lib/exe-discovery.ps1의 검증 절차를 그대로 옮겼다.
public partial class MainWindow
{
    private const string OfficialReleaseApi = "https://api.github.com/repos/Genymobile/scrcpy/releases/latest";
    private const string InstallRoot = @"C:\app";
    private bool _installingScrcpy;

    private sealed record OfficialRelease(string Tag, string AssetName, string DownloadUrl, string Sha256, long Size);

    private static HttpClient NewGithubClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("scrcpy-gui");
        return client;
    }

    private static async Task<OfficialRelease> GetOfficialReleaseAsync(HttpClient client)
    {
        var json = JsonNode.Parse(await client.GetStringAsync(OfficialReleaseApi))
            ?? throw new InvalidOperationException("릴리스 정보가 비어 있습니다.");
        var tag = json["tag_name"]?.GetValue<string>() ?? "";
        if (json["draft"]?.GetValue<bool>() == true || json["prerelease"]?.GetValue<bool>() == true
            || !Regex.IsMatch(tag, @"^v\d+\.\d+(\.\d+)?$"))
            throw new InvalidOperationException("최신 정식 릴리스 정보를 확인할 수 없습니다.");

        var assetName = $"scrcpy-win64-{tag}.zip";
        var assets = (json["assets"]?.AsArray() ?? []).Where(a => a?["name"]?.GetValue<string>() == assetName).ToList();
        if (assets.Count != 1) throw new InvalidOperationException($"공식 64비트 자산({assetName})을 찾지 못했습니다.");

        var asset = assets[0]!;
        var url = asset["browser_download_url"]?.GetValue<string>() ?? "";
        if (url != $"https://github.com/Genymobile/scrcpy/releases/download/{tag}/{assetName}")
            throw new InvalidOperationException("공식 GitHub 다운로드 경로가 아닙니다.");
        var digest = Regex.Match(asset["digest"]?.GetValue<string>() ?? "", "^sha256:([0-9a-fA-F]{64})$");
        if (!digest.Success) throw new InvalidOperationException("공식 SHA-256 digest가 없습니다.");
        var size = asset["size"]?.GetValue<long>() ?? 0;
        if (size <= 0) throw new InvalidOperationException("공식 자산의 크기가 올바르지 않습니다.");
        return new OfficialRelease(tag, assetName, url, digest.Groups[1].Value.ToLowerInvariant(), size);
    }

    private async void InstallOfficialScrcpy()
    {
        if (_installingScrcpy) return;
        _installingScrcpy = true;
        string? zipPath = null, stageDir = null;
        try
        {
            SetStatus("공식 scrcpy 최신 버전을 확인하는 중...");
            using var client = NewGithubClient();
            var release = await GetOfficialReleaseAsync(client);
            var target = Path.Combine(InstallRoot, $"scrcpy-win64-{release.Tag}");
            if (Directory.Exists(target))
            {
                SetStatus($"{release.Tag} 폴더가 이미 있어 설치하지 않았습니다: {target}");
                MessageBox.Show(this, $"{release.Tag} 설치 폴더가 이미 있습니다.\n기존 파일을 덮어쓰지 않으려고 설치하지 않았습니다.\n\n경로: {target}",
                    "scrcpy 설치", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var answer = MessageBox.Show(this,
                $"공식 scrcpy {release.Tag}(adb 포함)를 설치합니다.\n\n파일: {release.AssetName} ({release.Size / 1048576.0:F1} MiB)\n" +
                $"출처: github.com/Genymobile/scrcpy 공식 릴리스\nSHA-256: {release.Sha256}\n설치 경로: {target}\n\n" +
                "SHA-256 검증에 성공한 ZIP만 새 폴더에 풉니다. 기존 설치는 덮어쓰지 않습니다.",
                "공식 scrcpy 설치 확인", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (answer != MessageBoxResult.Yes) { SetStatus("설치를 취소했습니다."); return; }

            var token = Guid.NewGuid().ToString("N");
            zipPath = Path.Combine(Path.GetTempPath(), $"scrcpy-gui-{token}.zip");
            stageDir = Path.Combine(Path.GetTempPath(), $"scrcpy-gui-{token}");
            SetStatus($"공식 scrcpy {release.Tag} 다운로드 중...");
            await Task.Run(async () =>
            {
                await using (var file = File.Create(zipPath))
                await using (var stream = await client.GetStreamAsync(release.DownloadUrl))
                    await stream.CopyToAsync(file);

                string actual;
                await using (var read = File.OpenRead(zipPath))
                    actual = Convert.ToHexString(await SHA256.HashDataAsync(read)).ToLowerInvariant();
                if (actual != release.Sha256) throw new InvalidOperationException($"SHA-256 검증 실패: 기대 {release.Sha256}, 실제 {actual}");

                using (var archive = ZipFile.OpenRead(zipPath))
                    foreach (var entry in archive.Entries)
                    {
                        var name = entry.FullName.Replace('/', '\\');
                        if (Path.IsPathRooted(name) || Regex.IsMatch(name, @"(^|\\)\.\.(\\|$)") || Regex.IsMatch(name, "^[A-Za-z]:"))
                            throw new InvalidOperationException($"안전하지 않은 압축 경로가 있습니다: {entry.FullName}");
                    }
                ZipFile.ExtractToDirectory(zipPath, stageDir);
            });

            var scrcpyFiles = Directory.GetFiles(stageDir, "scrcpy.exe", SearchOption.AllDirectories);
            if (scrcpyFiles.Length != 1) throw new InvalidOperationException("압축 해제 결과에서 scrcpy.exe를 하나만 확인할 수 없습니다.");
            var exeDir = Path.GetDirectoryName(scrcpyFiles[0])!;
            if (!File.Exists(Path.Combine(exeDir, "adb.exe"))) throw new InvalidOperationException("압축 해제 결과에서 adb.exe를 찾지 못했습니다.");

            Directory.CreateDirectory(InstallRoot);
            Directory.Move(exeDir, target);

            var scrcpy = Path.Combine(target, "scrcpy.exe");
            var adb = Path.Combine(target, "adb.exe");
            if (!File.Exists(scrcpy) || !File.Exists(adb)) throw new InvalidOperationException("설치 후 scrcpy.exe 또는 adb.exe를 확인하지 못했습니다.");

            if (_controls.TryGetValue("scrcpyPath", out var scrcpyBox)) ((System.Windows.Controls.TextBox)scrcpyBox).Text = scrcpy;
            if (_controls.TryGetValue("adbPath", out var adbBox)) ((System.Windows.Controls.TextBox)adbBox).Text = adb;
            SaveConfiguredPaths();
            SetStatus($"공식 scrcpy {release.Tag} 설치 완료 — adb: {adb}");
        }
        catch (Exception ex)
        {
            SetStatus("scrcpy 설치 실패: " + ex.Message);
            MessageBox.Show(this, ex.Message, "scrcpy 설치 실패", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            try { if (zipPath is not null && File.Exists(zipPath)) File.Delete(zipPath); } catch { }
            try { if (stageDir is not null && Directory.Exists(stageDir)) Directory.Delete(stageDir, true); } catch { }
            _installingScrcpy = false;
        }
    }
}
