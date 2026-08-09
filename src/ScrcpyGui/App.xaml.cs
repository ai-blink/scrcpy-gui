namespace ScrcpyGui;

public partial class App : System.Windows.Application
{
    public App()
    {
        // WPF 글꼴 캐시는 WINDIR로 시스템 글꼴 URI를 만든다. 일부 자동화·단축 실행
        // 환경에서는 SystemRoot만 있고 WINDIR가 비어 있어 창 생성 전에 예외가 난다.
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("WINDIR")))
        {
            var systemRoot = Environment.GetEnvironmentVariable("SystemRoot");
            Environment.SetEnvironmentVariable("WINDIR", string.IsNullOrWhiteSpace(systemRoot) ? @"C:\Windows" : systemRoot);
        }
    }
}
