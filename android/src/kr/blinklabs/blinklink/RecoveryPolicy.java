package kr.blinklabs.blinklink;

/** Pure decision logic: unknown identity is never permission to enable ADB. */
public final class RecoveryPolicy {
    public enum Decision { PAUSED, PERMISSION, WIFI, IDENTITY, OTHER_WIFI, ALREADY_ON, ENABLE }
    public static Decision decide(boolean enabled, boolean permission, boolean wifi,
                                  String trusted, String current, boolean adbOn) {
        if (!enabled) return Decision.PAUSED;
        if (!permission) return Decision.PERMISSION;
        if (!wifi) return Decision.WIFI;
        if (trusted == null || trusted.isEmpty() || current == null || current.isEmpty()) return Decision.IDENTITY;
        if (!contains(trusted, current)) return Decision.OTHER_WIFI;
        return adbOn ? Decision.ALREADY_ON : Decision.ENABLE;
    }
    /** trusted = newline-separated SSIDs (one router often has separate 2.4/5 GHz names). Exact match only. */
    public static boolean contains(String trusted, String current) {
        if (trusted == null || !validSsid(current)) return false;
        for (String s : trusted.split("\n")) if (s.equals(current)) return true;
        return false;
    }
    /** SSIDs are arbitrary bytes; a control character (newline) would split the stored list or fake a label. */
    public static boolean validSsid(String s) {
        if (s == null || s.isEmpty()) return false;
        for (int i = 0; i < s.length(); i++) if (Character.isISOControl(s.charAt(i))) return false;
        return true;
    }
}
