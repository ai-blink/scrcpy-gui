package kr.blinklabs.blinklink;

import android.app.*;
import android.content.*;
import android.net.*;
import android.os.*;
import android.content.pm.ServiceInfo;

public final class LinkService extends Service {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private ConnectivityManager cm;
    private ConnectivityManager.NetworkCallback callback;
    private String last = "";
    private long windowStart;
    private int attempts;
    private long lastAttemptAt = -5000;
    private android.database.ContentObserver adbObserver;
    private final Runnable tick = new Runnable() {
        public void run() { check(); handler.postDelayed(this, 30000); }
    };
    private void report(String s) { if (!s.equals(last)) { last = s; LinkState.log(this, s); } }
    @Override public void onCreate() {
        super.onCreate();
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("link", "연결 복구 상태", NotificationManager.IMPORTANCE_LOW));
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);
        PendingIntent pause = PendingIntent.getService(this, 1, new Intent(this, LinkService.class).setAction("pause"), PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(this, "link").setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("Blink Link · 연결 복구 감시 중").setContentText("등록 Wi-Fi에서만 동작 · 눌러 상태 확인")
            .setContentIntent(open).setOngoing(true).addAction(new Notification.Action.Builder(null, "일시정지", pause).build()).build();
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        else startForeground(1, n);
        cm = getSystemService(ConnectivityManager.class);
        callback = new ConnectivityManager.NetworkCallback() {
            @Override public void onAvailable(Network n) { queue(); }
            @Override public void onLost(Network n) { queue(); }
            @Override public void onCapabilitiesChanged(Network n, NetworkCapabilities c) { queue(); }
            private void queue() { handler.post(() -> check()); }
        };
        cm.registerNetworkCallback(new NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(), callback);
        adbObserver = new android.database.ContentObserver(handler) {
            @Override public void onChange(boolean selfChange) { check(); }
        };
        getContentResolver().registerContentObserver(android.provider.Settings.Global.getUriFor(LinkState.KEY), false, adbObserver);
        handler.post(tick);
    }
    @Override public int onStartCommand(Intent i, int flags, int id) {
        if (i != null && "pause".equals(i.getAction())) {
            LinkState.prefs(this).edit().putBoolean("enabled", false).apply();
            LinkState.log(this, "자동 복구 일시정지 · 현재 디버깅 상태는 유지됩니다.");
        }
        if (!LinkState.enabled(this)) { stopSelf(); return START_NOT_STICKY; }
        check(); return START_STICKY;
    }
    private void check() {
        if (!LinkState.enabled(this)) { stopSelf(); return; }
        RecoveryPolicy.Decision d = RecoveryPolicy.decide(true, LinkState.permission(this), LinkState.wifi(this), LinkState.trusted(this), LinkState.ssid(this), LinkState.adb(this));
        switch (d) {
            case PERMISSION: report("권한 없음 · PC에서 최초 권한 부여 후 다시 확인하세요."); break;
            case WIFI: report("Wi-Fi 연결 대기"); break;
            case IDENTITY: report("Wi-Fi 이름 확인 불가 · 위치 권한 '항상 허용'과 위치 켜짐을 확인하세요."); break;
            case OTHER_WIFI:
                if (LinkState.prefs(this).getBoolean("owned", false)) {
                    if (LinkState.setAdb(this, false)) LinkState.prefs(this).edit().putBoolean("owned", false).apply();
                }
                report("다른 Wi-Fi · 자동 켜기 차단"); break;
            case ALREADY_ON:
                attempts = 0; windowStart = 0;
                report("무선 디버깅 켜짐 · PC 연결 여부는 PC에서 확인하세요."); break;
            case ENABLE:
                long now = SystemClock.elapsedRealtime();
                if (now - lastAttemptAt < 5000) break;
                if (now - windowStart >= 300000 || windowStart == 0) { windowStart = now; attempts = 0; }
                if (attempts >= 3) { report("재시도 대기 · Android 허용 창/개발자 옵션 확인 · 5분마다 최대 3회"); break; }
                attempts++; lastAttemptAt = now;
                if (LinkState.setAdb(this, true)) LinkState.prefs(this).edit().putBoolean("owned", true).apply();
                handler.postDelayed(() -> {
                    if (LinkState.enabled(this)) report(LinkState.adb(this) ? "무선 디버깅 켜짐 · PC 연결은 별도 확인" : "켜짐 미확인 · Android의 Wi-Fi 허용 창을 확인하세요.");
                }, 1500);
                break;
            default: break;
        }
    }
    @Override public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (adbObserver != null) getContentResolver().unregisterContentObserver(adbObserver);
        if (cm != null && callback != null) cm.unregisterNetworkCallback(callback);
        super.onDestroy();
    }
    @Override public IBinder onBind(Intent i) { return null; }
}
