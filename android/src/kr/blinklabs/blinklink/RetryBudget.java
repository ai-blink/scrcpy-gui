package kr.blinklabs.blinklink;

import java.util.ArrayDeque;

/** Rolling automatic request budget. A transient ON is not a budget reset. */
public final class RetryBudget {
    private final ArrayDeque<Long> requests = new ArrayDeque<>();
    public RetryBudget(String saved) {
        if (saved != null && !saved.isEmpty()) {
            for (String part : saved.split(",")) {
                try { requests.addLast(Long.parseLong(part)); }
                catch (NumberFormatException ignored) { }
            }
        }
    }
    public boolean take(long now) {
        while (!requests.isEmpty() && (now < requests.peekFirst() || now - requests.peekFirst() >= 300000)) requests.removeFirst();
        if (requests.size() >= 3 || (!requests.isEmpty() && now - requests.peekLast() < 5000)) return false;
        requests.addLast(now);
        return true;
    }
    public String save() {
        StringBuilder result = new StringBuilder();
        for (long time : requests) { if (result.length() > 0) result.append(','); result.append(time); }
        return result.toString();
    }
}
