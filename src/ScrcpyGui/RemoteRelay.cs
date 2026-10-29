using System.Runtime.InteropServices;
using static ScrcpyGui.RemoteNative;

namespace ScrcpyGui;

internal sealed record RemoteHit(RemoteAction Action, PixelRect Bounds, nint Handle);
internal sealed record RelayConfiguration(MirrorTarget? Target, RemoteSettings Settings, RemoteHit[] Hits, PixelRect Client, PixelRect Video, bool Enabled, long Revision);
internal sealed record RelayView(Point Logical, bool Busy, RemoteAction? Hover, double Progress, string Status, int Completed, long LastDurationMs, long MedianMs = 0, long MaxMs = 0, bool InputReady = false);

// One clock owns dwell and repeat. Completion, rather than submission, starts the
// repeat interval. No command queue can replay input after Stop or target loss.
internal sealed class RemoteActivation
{
    public RemoteAction? Hover { get; private set; }
    private long _due;
    private bool _fired;
    public double Progress(long now, int dwell, int repeat = 0)
    {
        if (Hover is null || _due == long.MaxValue || _fired && (repeat <= 0 || !Scroll(Hover.Value))) return 0;
        var duration = _fired ? repeat : dwell;
        return duration == 0 ? 1 : Math.Clamp(1 - (double)(_due - now) / duration, 0, 1);
    }
    public void Observe(RemoteAction? hover, long now, int dwell)
    {
        if (Hover == hover) return;
        Hover = hover; _due = now + dwell; _fired = false;
    }
    public bool Due(long now, RemoteSettings s, bool held)
    {
        if (Hover is null || now < _due) return false;
        if (s.Activation == "click") return held && s.HoldRepeat && _fired && Scroll(Hover.Value);
        return !_fired || s.Repeat && Scroll(Hover.Value);
    }
    public void Fired() { _fired = true; _due = long.MaxValue; }
    public void Completed(long now, int repeat) => _due = now + repeat;
    public void Reset() { Hover = null; _fired = false; _due = long.MaxValue; }
    public static bool Scroll(RemoteAction action) => action is RemoteAction.Up or RemoteAction.Down;
}

internal sealed class RemoteRelay : IDisposable
{
    private readonly object _gate = new();
    private readonly Thread? _thread;
    private readonly Action<Point> _moveTo;
    private readonly Func<Point, nint> _windowAt;
    private readonly Action<Point, int, Point> _wheelPulse;
    private readonly HookProc _hookProc;
    private readonly RemoteActivation _activation = new();
    private RelayConfiguration? _config;
    private RelayView _view = new(default, false, null, 0, "대상 창을 선택하세요.", 0, 0);
    private uint _threadId;
    private nint _hook;
    private Point _logical, _destination;
    private bool _relaying, _leftOwned, _held, _disposed;
    private RemoteAction? _pressed;
    private int _phase, _completed;
    private long _deadline, _started, _revision, _duration;
    private long _stoppedRevision = long.MinValue;
    private RemoteAction? _click, _active;
    private RelayConfiguration? _running;
    private string _status = "대상 창을 선택하세요.";
    private readonly Queue<long> _durations = new();
    private RemoteAction? _utility;
    private bool _inputReady;
    public RemoteRelay() : this(true, MoveTo, p => GetAncestor(WindowFromPoint(p), 2)) { }
    internal RemoteRelay(bool startThread, Action<Point> moveTo, Func<Point, nint> windowAt, Action<Point, int, Point>? wheelPulse = null)
    {
        _moveTo = moveTo; _windowAt = windowAt; _wheelPulse = wheelPulse ?? WheelPulse;
        _hookProc = MouseHook;
        if (!startThread) return;
        _thread = new Thread(Run) { IsBackground = true, Name = "scrcpy pointer relay" };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
    }
    public void Configure(RelayConfiguration config) { lock (_gate) _config = config; }
    public RelayView View { get { lock (_gate) return _view; } }
    public RemoteAction? TakeUtility() { lock (_gate) { var action = _utility; _utility = null; return action; } }

    private void Run()
    {
        _threadId = GetCurrentThreadId();
        PeekMessage(out _, 0, 0, 0, 0);
        GetCursorPos(out _logical);
        _hook = SetWindowsHookEx(14, _hookProc, GetModuleHandle(null), 0);
        if (_hook == 0) { Publish("포인터 감시를 시작하지 못했습니다. 조작판을 중지합니다."); return; }
        var timer = SetTimer(0, 0, 15, 0);
        if (timer == 0) { UnhookWindowsHookEx(_hook); Publish("입력 타이머를 시작하지 못했습니다."); return; }
        _inputReady = true;
        Publish("입력 준비됨");
        try
        {
            while (GetMessage(out var message, 0, 0, 0) > 0)
            {
                if (message.Id == 0x113) Tick();
            }
        }
        finally
        {
            _inputReady = false; Cancel("조작판 종료"); KillTimer(0, timer); UnhookWindowsHookEx(_hook);
        }
    }

    private nint MouseHook(int code, nint message, nint data)
    {
        if (code < 0) return CallNextHookEx(0, code, message, data);
        var m = Marshal.PtrToStructure<HookData>(data);
        if (m.Extra == Tag) return CallNextHookEx(0, code, message, data);
        var kind = (int)message;
        if (kind == Move)
        {
            GetCursorPos(out var previous);
            _logical = ObserveMovement(_logical, m.Point, previous, _relaying, m.Flags);
            return _relaying ? 1 : CallNextHookEx(0, code, message, data);
        }
        RelayConfiguration? config; lock (_gate) config = _config;
        var hit = Hit(config);
        if (kind == LeftDown)
        {
            if (!_relaying) _logical = m.Point;
            hit = Hit(config);
            if (_leftOwned) return 1; // duplicate assistive Down belongs to this press
            if (hit is not null || _relaying)
            {
                _leftOwned = true; _held = true; _pressed = hit?.Action;
                if (hit?.Action is RemoteAction.Stop or RemoteAction.Settings || config?.Settings.HoldRepeat == true && config.Settings.Activation == "click") _click = hit?.Action;
                return 1;
            }
        }
        if (kind == LeftUp && _leftOwned)
        {
            // In dwell mode an eye mouse may also synthesize its own click at
            // the charge deadline. Consume it without executing the action twice.
            if (hit?.Action == _pressed && config?.Settings.Activation == "click" && !config.Settings.HoldRepeat && _pressed is not RemoteAction.Stop and not RemoteAction.Settings) _click = _pressed;
            _leftOwned = _held = false; _pressed = null; return 1;
        }
        // Never let an external button press hit Android during a cursor excursion.
        if (_relaying && kind is 0x204 or 0x205 or 0x207 or 0x208 or 0x20B or 0x20C) { _click = RemoteAction.Stop; return 1; }
        return CallNextHookEx(0, code, message, data);
    }
    private RemoteHit? Hit(RelayConfiguration? config)
    {
        var hit = config?.Hits.FirstOrDefault(h => h.Bounds.Contains(_logical.X, _logical.Y));
        if (hit is null) return null;
        // Always test the logical location, including during an excursion. A
        // non-activating popup over the button must cancel the original hover.
        return _windowAt(_logical) == hit.Handle ? hit : null;
    }
    internal static Point ObserveMovement(Point logical, Point incoming, Point actualBefore, bool relaying, uint flags) =>
        relaying && (flags & 1) == 0 ? new(logical.X + incoming.X - actualBefore.X, logical.Y + incoming.Y - actualBefore.Y) : incoming;
    private void Tick()
    {
        RelayConfiguration? config; lock (_gate) config = _config;
        var now = Environment.TickCount64;
        try
        {
            if (_disposed) { Cancel("종료"); PostThreadMessage(_threadId, 0x12, 0, 0); return; }
            if (config is null) return;
            // Outside an excursion the desktop cursor is authoritative. This also
            // prevents stale dwell when Windows has removed a low-level hook.
            if (!_relaying && GetCursorPos(out var desktop)) _logical = desktop;
            if (_revision != config.Revision)
            {
                Cancel("설정 변경 · 새 응시로 시작하세요."); _revision = config.Revision;
            }
            var hit = Hit(config)?.Action;
            if (!config.Enabled && hit is not RemoteAction.Stop and not RemoteAction.Settings) hit = null;
            _activation.Observe(hit, now, config.Settings.DwellMs);
            var click = _click; _click = null;
            if (click == RemoteAction.Stop)
            {
                _stoppedRevision = config.Revision; _activation.Fired(); Cancel("일시 정지");
                lock (_gate) _utility = RemoteAction.Stop;
                return;
            }
            if (hit is RemoteAction.Stop or RemoteAction.Settings && (click == hit || _activation.Due(now, config.Settings, _held)))
            {
                _stoppedRevision = config.Revision; _activation.Fired(); Cancel(hit == RemoteAction.Stop ? "일시 정지" : "설정 중");
                lock (_gate) _utility = hit;
                return;
            }
            if (!config.Enabled || _stoppedRevision == config.Revision || config.Target is null || !Valid(config.Target))
            { Cancel(config.Enabled ? "대상 창을 사용할 수 없습니다. 다시 선택하세요." : "일시 정지 · 설정에서 시작하세요."); return; }
            if (_phase != 0)
            {
                if (hit != _active || config.Revision != _running!.Revision)
                { Cancel("버튼 이탈 · 입력 중지"); return; }
                if (_phase == 3) { Advance(now); return; }
                if (GetCursorPos(out var actual) && (Math.Abs(actual.X - _destination.X) > 1 || Math.Abs(actual.Y - _destination.Y) > 1))
                {
                    // An external move escaped the hook. Keep that user's current
                    // position instead of snapping to the stale return point.
                    _logical = actual;
                    throw new InvalidOperationException("실제 포인터 이동으로 왕복을 중지했습니다. 다시 응시하세요.");
                }
                Advance(now);
                return;
            }
            var action = click ?? (_activation.Due(now, config.Settings, _held) ? hit : null);
            if (action is null || action is RemoteAction.Stop or RemoteAction.Settings) return;
            // A drag started in another app still belongs to that app.
            if (!_leftOwned && ButtonsHeld()) { _status = "사용자 버튼 해제 대기"; return; }
            _activation.Fired(); _active = action; _running = config; _started = now;
            if (!string.IsNullOrEmpty(config.Target.Error)) throw new InvalidOperationException(config.Target.Error);
            if (RemoteActivation.Scroll(action.Value))
            {
                if (ModifiersHeld()) throw new InvalidOperationException("보조키 해제 후 다시 선택하세요.");
                if (config.Settings.BringForward) Focus(config.Target);
                else if (GetForegroundWindow() != config.Target.Handle) throw new InvalidOperationException("미러링 창이 활성 상태가 아닙니다. 창을 선택하거나 가림 정책을 바꾸세요.");
                var point = RemoteLayout.ScrollPoint(config.Video, config.Settings.U, config.Settings.V);
                _destination = new(point.X, point.Y);
                if (!config.Client.Contains(point.X, point.Y)) throw new InvalidOperationException("스크롤 지점이 영상 창 밖입니다. 다시 지정하세요.");
                if (!AtTarget(config.Target, _destination)) throw new InvalidOperationException("영상 지점이 다른 창에 가려졌습니다. 입력을 중지했습니다.");
                if (config.Settings.ScrollMode == "atomic")
                {
                    StartAtomic(config);
                    return;
                }
                _relaying = true; _phase = 1;
                _moveTo(_destination); _deadline = Environment.TickCount64 + config.Settings.ArrivalMs;
                _status = "영상 도착 대기";
            }
            else
            {
                Shortcut(config.Target, action.Value);
                Complete(Environment.TickCount64);
            }
        }
        catch (Exception ex) { Cancel(ex.Message); _activation.Fired(); }
        finally { Publish(_status); }
    }
    private void Advance(long now)
    {
        if (now < _deadline) return;
        var c = _running!;
        if (_phase == 3) { Complete(Environment.TickCount64); return; }
        if (_phase == 1)
        {
            if (!GetCursorPos(out var actual) || Math.Abs(actual.X - _destination.X) > 1 || Math.Abs(actual.Y - _destination.Y) > 1)
                throw new InvalidOperationException("도착 좌표가 변경되어 휠을 보내지 않았습니다.");
            if (ModifiersHeld() || !Valid(c.Target!) || GetForegroundWindow() != c.Target!.Handle || ClientBounds(c.Target.Handle) != c.Client || !AtTarget(c.Target, _destination))
                throw new InvalidOperationException("대상 이동/가림/포커스 변경으로 휠을 중지했습니다.");
            Wheel((_active == RemoteAction.Up ? 120 : -120) * c.Settings.Notches);
            _phase = 2; _deadline = Environment.TickCount64 + c.Settings.AfterMs; _status = "휠 제출 · 복귀 대기";
        }
        else
        {
            Restore(); Complete(Environment.TickCount64);
        }
    }
    private void StartAtomic(RelayConfiguration config)
    {
        _wheelPulse(_destination, (_active == RemoteAction.Up ? 120 : -120) * config.Settings.Notches, _logical);
        _phase = 3; _deadline = Environment.TickCount64 + config.Settings.SettleMs;
        _status = "한 번에 스크롤 · 복귀 후 대기";
        if (config.Settings.SettleMs == 0) Complete(Environment.TickCount64);
    }
    private void Restore()
    {
        if (!_relaying) return;
        try { _moveTo(_logical); }
        finally { _relaying = false; }
    }
    private void Complete(long now)
    {
        _phase = 0; _duration = now - _started; _completed++;
        _durations.Enqueue(_duration); if (_durations.Count > 50) _durations.Dequeue();
        _activation.Completed(now, _running!.Settings.RepeatMs);
        _status = $"명령 전송 {_completed}회 · 최근 {_duration}ms";
    }
    private void Cancel(string message)
    {
        try { Restore(); }
        catch (Exception ex) { message = $"커서 복귀 실패: {ex.Message}"; }
        _phase = 0; _click = null; _active = null; _running = null;
        _status = message;
    }
    private void Publish(string status)
    {
        var progress = _config is { } c ? _activation.Progress(Environment.TickCount64, c.Settings.DwellMs,
            (c.Settings.Activation == "dwell" ? c.Settings.Repeat : c.Settings.HoldRepeat && _held) ? c.Settings.RepeatMs : 0) : 0;
        var times = _durations.Order().ToArray();
        lock (_gate) _view = new(_logical, _relaying, _activation.Hover, progress, status, _completed, _duration,
            times.Length == 0 ? 0 : times[times.Length / 2], times.Length == 0 ? 0 : times[^1], _inputReady);
    }
    public void Dispose()
    {
        if (_disposed) return; _disposed = true;
        if (_threadId != 0) PostThreadMessage(_threadId, 0x12, 0, 0);
        if (_thread is null) Cancel("조작판 종료");
        else _thread.Join(1000);
    }
}
