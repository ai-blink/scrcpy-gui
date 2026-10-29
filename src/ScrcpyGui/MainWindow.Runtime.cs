using System.Diagnostics;
using System.Windows;
using System.Windows.Media;

namespace ScrcpyGui;

public partial class MainWindow
{
    private async Task MonitorSessionAsync(Process process, bool backgroundOnly)
    {
        var lines = new Queue<string>(); var gate = new object();
        DataReceivedEventHandler receive = (_, e) =>
        {
            if (string.IsNullOrWhiteSpace(e.Data)) return;
            lock (gate) { lines.Enqueue(e.Data); while (lines.Count > 10) lines.Dequeue(); }
        };
        process.ErrorDataReceived += receive; process.OutputDataReceived += receive;
        try
        {
            process.BeginErrorReadLine(); process.BeginOutputReadLine();
            for (var attempt = 0; attempt < 40 && !process.HasExited; attempt++)
            {
                process.Refresh();
                if (process.MainWindowHandle != 0 || backgroundOnly)
                {
                    if (ReferenceEquals(_sessionProcess, process))
                    {
                        SessionStatusText.Text = backgroundOnly ? "백그라운드 세션 실행 중 · 변경한 옵션은 다음 실행에 적용" : "미러링 실행 중 · 변경한 옵션은 다음 실행에 적용";
                        SessionStatusText.Foreground = Brushes.LightGreen;
                        RunButton.Content = "새 창 실행"; RunButton.IsEnabled = true;
                        MarkDeviceUsed(); await _remoteControls.Refresh();
                    }
                    break;
                }
                await Task.Delay(250, _lifetime.Token);
            }
            if (!process.HasExited && ReferenceEquals(_sessionProcess, process) && !RunButton.IsEnabled)
            {
                SessionStatusText.Text = "프로세스 실행 중 · 영상 창은 아직 확인되지 않았습니다.";
                RunButton.IsEnabled = true;
            }
            await process.WaitForExitAsync(_lifetime.Token);
            if (!ReferenceEquals(_sessionProcess, process)) return;
            var exitCode = process.ExitCode;
            SessionStatusText.Text = exitCode == 0 ? "미러링 세션 종료" : $"미러링 실패 · 종료 코드 {exitCode}";
            SessionStatusText.Foreground = exitCode == 0 ? Brushes.LightSteelBlue : Brushes.Salmon;
            string details; lock (gate) details = string.Join("\n", lines);
            if (exitCode != 0) SetStatus(details.Length == 0 ? "scrcpy가 종료됐습니다. 연결 상태와 실행 옵션을 확인하세요." : details[..Math.Min(details.Length, 1400)]);
        }
        catch (OperationCanceledException) { /* Closing this GUI never terminates the mirror. */ }
        catch (Exception ex)
        {
            if (ReferenceEquals(_sessionProcess, process)) SetStatus("세션 상태 확인 실패: " + ex.Message);
        }
        finally
        {
            process.ErrorDataReceived -= receive; process.OutputDataReceived -= receive;
            if (ReferenceEquals(_sessionProcess, process)) { _sessionProcess = null; RunButton.IsEnabled = true; RunButton.Content = "실행"; }
            process.Dispose();
        }
    }
    private void CancelConnection_OnClick(object sender, RoutedEventArgs e)
    {
        _connectionCancellation?.Cancel(); SetStatus("연결 작업을 취소하고 있습니다…");
    }
    private bool BeginConnectionWork()
    {
        if (_connectionCancellation is not null) return false;
        _connectionCancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        CancelConnectionButton.Visibility = Visibility.Visible;
        DiscoverButton.IsEnabled = RefreshButton.IsEnabled = false;
        return true;
    }
    private void EndConnectionWork()
    {
        _connectionCancellation?.Dispose(); _connectionCancellation = null;
        CancelConnectionButton.Visibility = Visibility.Collapsed;
        DiscoverButton.IsEnabled = RefreshButton.IsEnabled = true;
    }
}
