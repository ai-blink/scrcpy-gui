using System.IO;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace ScrcpyGui;

internal sealed record BlinkAdbResult(int ExitCode, string Output);
internal sealed record BlinkSetupResult(string Serial, string UserId);

/// <summary>Each device command is pinned to the target chosen before the operation starts.</summary>
internal sealed class BlinkLinkProvisioner(Func<IReadOnlyList<string>, CancellationToken, TimeSpan, Task<BlinkAdbResult>> adb)
{
    internal const string Package = "kr.blinklabs.blinklink";
    internal const string Permission = "android.permission.WRITE_SECURE_SETTINGS";
    internal const string Version = "0.3.2";
    internal const string ApkSha256 = "affd1245bc6e150ee0c1ffd2ea18e0eaa0231fac66483002819c0419841cce61";

    internal async Task<BlinkSetupResult> PrepareAsync(string serial, string apk, IProgress<string>? progress, CancellationToken cancellation)
    {
        if (string.IsNullOrWhiteSpace(serial) || serial.StartsWith('-') || serial.Any(char.IsWhiteSpace) || serial.Any(char.IsControl))
            throw new InvalidOperationException("설정할 휴대폰을 목록에서 선택하세요.");
        if (!File.Exists(apk)) throw new FileNotFoundException("설치 파일을 찾을 수 없습니다. Blink Link가 포함된 배포본을 다시 받으세요.", apk);
        using (var stream = File.OpenRead(apk))
            if (!Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellation)).Equals(ApkSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("설치 파일 검증에 실패했습니다. Blink Link가 포함된 배포본을 다시 받으세요.");

        async Task<string> Run(string stage, TimeSpan timeout, params string[] args)
        {
            cancellation.ThrowIfCancellationRequested();
            progress?.Report(stage);
            var reply = await adb(new[] { "-s", serial }.Concat(args).ToArray(), cancellation, timeout);
            cancellation.ThrowIfCancellationRequested();
            if (reply.ExitCode != 0) throw new InvalidOperationException(stage + " 실패 · " + reply.Output.Trim());
            return reply.Output.Trim();
        }
        async Task Connected()
        {
            if (await Run("휴대폰 연결 확인", TimeSpan.FromSeconds(12), "get-state") != "device")
                throw new InvalidOperationException("선택한 휴대폰이 연결되지 않았습니다. 다시 연결한 뒤 시도하세요.");
        }
        await Connected();
        var user = await Run("휴대폰 사용자 확인", TimeSpan.FromSeconds(12), "shell", "am", "get-current-user");
        if (!Regex.IsMatch(user, "^[0-9]+$")) throw new InvalidOperationException("휴대폰 사용자를 확인하지 못했습니다. 개인 사용자 화면에서 다시 시도하세요.");
        var installed = await Run("Blink Link 설치 · 기존 데이터 유지", TimeSpan.FromMinutes(2), "install", "--user", user, "-r", apk);
        if (!Regex.IsMatch(installed, @"(?m)^Success\s*$")) throw new InvalidOperationException("설치 완료를 확인하지 못했습니다 · " + installed);
        await Connected();
        var currentUser = await Run("휴대폰 사용자 재확인", TimeSpan.FromSeconds(12), "shell", "am", "get-current-user");
        if (currentUser != user) throw new InvalidOperationException("도중에 휴대폰 사용자가 바뀌었습니다. 대상 사용자를 확인하고 다시 시도하세요.");
        await Run("최초 권한 설정", TimeSpan.FromSeconds(20), "shell", "pm", "grant", "--user", user, Package, Permission);
        var permission = await Run("권한 적용 확인", TimeSpan.FromSeconds(12), "shell", "dumpsys", "package", Package);
        if (!HasSecureSettingsPermission(permission, user)) throw new InvalidOperationException("설치는 됐지만 권한 적용을 확인하지 못했습니다. 휴대폰 보안 정책과 연결을 확인하세요.");
        var opened = await Run("휴대폰에서 Blink Link 열기", TimeSpan.FromSeconds(20), "shell", "am", "start", "--user", user, "-n", Package + "/.MainActivity");
        if (Regex.IsMatch(opened, @"(?im)^\s*(Error|Exception)|Permission Denial"))
            throw new InvalidOperationException("설치와 권한 설정은 끝났지만 앱을 열지 못했습니다. 휴대폰에서 Blink Link를 열어주세요. · " + opened);
        return new(serial, user);
    }
    internal static bool HasSecureSettingsPermission(string dump,string user)
    {
        if (!dump.Contains("Package [" + Package + "]",StringComparison.Ordinal)) return false;
        var users=Regex.Matches(dump,@"(?m)^ {4}User ([0-9]+):[^\r\n]*");
        if(users.Count==0)return false;
        bool Granted(string value)=>Regex.IsMatch(value,@"(?m)^\s*android\.permission\.WRITE_SECURE_SETTINGS:\s*granted=true\b");
        // Development install permissions are global; runtime permissions are user-specific.
        if(Granted(dump[..users[0].Index]))return true;
        for(int i=0;i<users.Count;i++)if(users[i].Groups[1].Value==user){int end=i+1<users.Count?users[i+1].Index:dump.Length;return Granted(dump[users[i].Index..end]);}
        return false;
    }

}
