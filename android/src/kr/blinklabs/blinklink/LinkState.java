package kr.blinklabs.blinklink;

import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.*;
import android.net.wifi.*;
import android.provider.Settings;
import java.text.SimpleDateFormat;
import java.util.*;

public final class LinkState {
    public static final String KEY = "adb_wifi_enabled";
    public static android.content.SharedPreferences prefs(Context c) { return c.getSharedPreferences("link", 0); }
    public static boolean enabled(Context c) { return prefs(c).getBoolean("enabled", false); }
    public static boolean permission(Context c) { return c.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED; }
    public static boolean adb(Context c) { return Settings.Global.getInt(c.getContentResolver(), KEY, 0) == 1; }
    public static boolean wifi(Context c) {
        ConnectivityManager cm = c.getSystemService(ConnectivityManager.class);
        for (Network n : cm.getAllNetworks()) {
            NetworkCapabilities caps = cm.getNetworkCapabilities(n);
            if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return true;
        }
        return false;
    }
    @SuppressWarnings("deprecation") public static String ssid(Context c) {
        try {
            WifiInfo i = c.getSystemService(WifiManager.class).getConnectionInfo();
            String s = i == null ? null : i.getSSID();
            if (s == null || s.equals(WifiManager.UNKNOWN_SSID) || s.equals("0x") || s.isEmpty()) return "";
            if (s.startsWith("\"") && s.endsWith("\"")) s = s.substring(1, s.length()-1);
            return s;
        } catch (SecurityException e) { return ""; }
    }
    public static String trusted(Context c) { return prefs(c).getString("trusted", ""); }
    public static synchronized void log(Context c, String message) {
        String line = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.KOREA).format(new Date()) + "  " + message;
        String old = prefs(c).getString("log", "");
        String result = line + "\n" + old;
        if (result.length() > 6000) result = result.substring(0, 6000);
        prefs(c).edit().putString("status", message).putString("log", result).apply();
    }
    public static boolean setAdb(Context c, boolean on) {
        try {
            if (!permission(c)) { log(c, "PC에서 최초 1회 권한 부여가 필요합니다."); return false; }
            boolean accepted = Settings.Global.putInt(c.getContentResolver(), KEY, on ? 1 : 0);
            log(c, accepted ? (on ? "켜기 요청 전송 · Android 확인 창 또는 결과 확인 중" : "끄기 요청 전송") : "Android가 설정 변경을 거절했습니다.");
            return accepted;
        } catch (SecurityException | IllegalArgumentException e) {
            log(c, "설정 변경 실패: " + e.getClass().getSimpleName()); return false;
        }
    }
    public static void start(Context c) {
        try { c.startForegroundService(new Intent(c, LinkService.class)); }
        catch (RuntimeException e) { log(c, "감시 시작 제한 · 앱을 열어 다시 시작하세요: " + e.getClass().getSimpleName()); }
    }
}
