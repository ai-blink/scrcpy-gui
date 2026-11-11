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
        if (!trusted.equals(current)) return Decision.OTHER_WIFI;
        return adbOn ? Decision.ALREADY_ON : Decision.ENABLE;
    }
}
