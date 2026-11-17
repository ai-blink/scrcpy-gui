package kr.blinklabs.blinklink;

import android.app.Notification;
import android.app.NotificationManager;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.Icon;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Bundle;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import android.util.Base64;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Sends newly posted user-facing notifications to the PC.
 * The PC reads them through `adb forward tcp:N localabstract:blinklink_notify`;
 * only adbd (shell/root uid) may connect, so other apps on the phone cannot read them.
 */
public final class NotifyListener extends NotificationListenerService {
    static final String SOCKET = "blinklink_notify";
    private static final int SHELL_UID = 2000, ROOT_UID = 0, ICON_PX = 96;
    private final List<LocalSocket> clients = new CopyOnWriteArrayList<>();
    // Apps re-post the same notification for ranking or silent updates; forward only content changes.
    private final Map<String, String> lastContent = new LinkedHashMap<String, String>(64, 0.75f, true) {
        @Override protected boolean removeEldestEntry(Map.Entry<String, String> eldest) { return size() > 200; }
    };
    // The screen each forwarded notification opens. People often read the message on the phone first, which
    // removes the notification; the PC toast should still open that chat, not the app's first screen.
    private final Map<String, android.app.PendingIntent> targets = new LinkedHashMap<String, android.app.PendingIntent>(64, 0.75f, true) {
        @Override protected boolean removeEldestEntry(Map.Entry<String, android.app.PendingIntent> eldest) { return size() > 200; }
    };
    private LocalServerSocket server;
    private ScheduledExecutorService worker;
    private volatile boolean stopping;

    @Override public void onListenerConnected() { start(); }
    @Override public void onListenerDisconnected() { stop(); }
    @Override public void onDestroy() { stop(); super.onDestroy(); }

    private synchronized void start() {
        if (server != null) return;
        try { server = new LocalServerSocket(SOCKET); }
        catch (IOException e) { LinkState.log(this, "PC 알림 전달 시작 실패 · " + e.getMessage()); return; }
        stopping = false;
        worker = Executors.newSingleThreadScheduledExecutor();
        // The ping lets both sides notice a dead adb connection.
        worker.scheduleWithFixedDelay(() -> broadcast("{\"type\":\"ping\"}"), 30, 30, TimeUnit.SECONDS);
        final LocalServerSocket listening = server;
        Thread acceptor = new Thread(() -> {
            while (!stopping) {
                LocalSocket socket;
                try { socket = listening.accept(); } catch (IOException e) { return; }
                if (stopping) { close(socket); return; }
                try {
                    int uid = socket.getPeerCredentials().getUid();
                    if (uid != SHELL_UID && uid != ROOT_UID) { close(socket); continue; }
                    socket.getOutputStream().write("{\"type\":\"hello\",\"version\":2}\n".getBytes(StandardCharsets.UTF_8));
                    clients.add(socket);
                    listen(socket);
                } catch (IOException e) { close(socket); }
            }
        }, "blinklink-notify");
        acceptor.setDaemon(true);
        acceptor.start();
    }

    private synchronized void stop() {
        if (server == null) return;
        stopping = true;
        // LocalServerSocket.close() does not unblock accept(); a throwaway connection does.
        LocalSocket wake = new LocalSocket();
        try { wake.connect(new LocalSocketAddress(SOCKET)); } catch (IOException ignored) { }
        close(wake);
        try { server.close(); } catch (IOException ignored) { }
        server = null;
        for (LocalSocket client : clients) close(client);
        clients.clear();
        if (worker != null) worker.shutdownNow();
        worker = null;
        // Notification access was withdrawn: do not keep other apps' screens around.
        synchronized (targets) { targets.clear(); }
        synchronized (lastContent) { lastContent.clear(); }
    }

    // OpenActivity reports here whether the notification's screen actually started.
    private static final Map<String, java.util.concurrent.CompletableFuture<String>> pendingOpens = new java.util.concurrent.ConcurrentHashMap<>();

    static void opened(String request, String error) {
        java.util.concurrent.CompletableFuture<String> result = request == null ? null : pendingOpens.remove(request);
        if (result != null) result.complete(error);
    }

    /** Reads PC commands: {"type":"open","key":...,"display":N} opens that notification's own target screen. */
    private void listen(LocalSocket socket) {
        Thread reader = new Thread(() -> {
            try {
                java.io.BufferedReader in = new java.io.BufferedReader(new java.io.InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
                String line;
                while ((line = in.readLine()) != null) {
                    try {
                        JSONObject command = new JSONObject(line);
                        if ("open".equals(command.optString("type"))) reply(socket, open(command.optString("key"), command.optInt("display", -1)));
                    } catch (org.json.JSONException ignored) { }
                }
            } catch (IOException ignored) { }
            clients.remove(socket);
            close(socket);
        }, "blinklink-notify-in");
        reader.setDaemon(true);
        reader.start();
    }

    private String open(String key, int display) {
        if (key.isEmpty() || display < 0) return "잘못된 요청";
        StatusBarNotification[] found;
        try { found = getActiveNotifications(new String[]{key}); } catch (RuntimeException e) { return "알림 조회 실패"; }
        Notification n = found == null || found.length == 0 ? null : found[0].getNotification();
        // A live notification decides by itself; the remembered screen is only for one already removed.
        android.app.PendingIntent target;
        if (n != null) target = n.contentIntent;
        else synchronized (targets) { target = targets.get(key); }
        if (target == null) return n == null ? "휴대폰에서 이미 지운 알림" : "열 화면이 없는 알림";
        // The overlay app-op (granted by the PC) lets this service start its own invisible activity there;
        // that visible activity then runs the notification's action, which Android allows.
        String request = java.util.UUID.randomUUID().toString();
        java.util.concurrent.CompletableFuture<String> result = new java.util.concurrent.CompletableFuture<>();
        pendingOpens.put(request, result);
        android.content.Intent trampoline = new android.content.Intent(this, OpenActivity.class)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK | android.content.Intent.FLAG_ACTIVITY_MULTIPLE_TASK | android.content.Intent.FLAG_ACTIVITY_NO_ANIMATION)
            .putExtra(OpenActivity.TARGET, target)
            .putExtra(OpenActivity.REQUEST, request);
        try { startActivity(trampoline, android.app.ActivityOptions.makeBasic().setLaunchDisplayId(display).toBundle()); }
        catch (RuntimeException e) { pendingOpens.remove(request); return "실행 거부 · " + e.getMessage(); }
        String error;
        try { error = result.get(5, TimeUnit.SECONDS); }
        catch (java.util.concurrent.TimeoutException e) { error = "휴대폰이 화면 열기에 응답하지 않음"; }
        catch (InterruptedException | java.util.concurrent.ExecutionException e) { error = "화면 열기 확인 실패"; }
        finally { pendingOpens.remove(request); }
        if (!error.isEmpty()) {
            // A used or cancelled screen will not work next time either.
            if (n == null) synchronized (targets) { targets.remove(key); }
            return error;
        }
        if (n != null && (n.flags & Notification.FLAG_AUTO_CANCEL) != 0) cancelNotification(key);
        return "";
    }

    private static void reply(LocalSocket socket, String error) {
        try {
            JSONObject json = new JSONObject();
            json.put("type", "opened");
            json.put("ok", error.isEmpty());
            json.put("reason", error);
            synchronized (socket) { socket.getOutputStream().write((json + "\n").getBytes(StandardCharsets.UTF_8)); }
        } catch (IOException | org.json.JSONException ignored) { }
    }

    @Override public void onNotificationPosted(StatusBarNotification sbn) {
        ScheduledExecutorService current = worker;
        if (current == null || clients.isEmpty() || !forwardable(sbn)) return;
        current.execute(() -> {
            String line = describe(sbn);
            if (line != null) broadcast(line);
        });
    }

    private boolean forwardable(StatusBarNotification sbn) {
        Notification n = sbn.getNotification();
        if (sbn.getPackageName().equals(getPackageName()) || sbn.isOngoing() || !sbn.isClearable()) return false;
        if ((n.flags & (Notification.FLAG_GROUP_SUMMARY | Notification.FLAG_FOREGROUND_SERVICE)) != 0) return false;
        Ranking ranking = new Ranking();
        RankingMap map = getCurrentRanking();
        if (map != null && map.getRanking(sbn.getKey(), ranking)) {
            // Silent channels and notifications blocked by Do Not Disturb stay on the phone.
            if (ranking.getImportance() < NotificationManager.IMPORTANCE_DEFAULT || !ranking.matchesInterruptionFilter()) return false;
        }
        return true;
    }

    private String describe(StatusBarNotification sbn) {
        Notification n = sbn.getNotification();
        // Keep the newest screen even when the text did not change (apps may recreate the intent),
        // and forget it when the update no longer opens anything.
        synchronized (targets) {
            if (n.contentIntent != null) targets.put(sbn.getKey(), n.contentIntent);
            else targets.remove(sbn.getKey());
        }
        Bundle extras = n.extras;
        String title = text(extras.getCharSequence(Notification.EXTRA_TITLE));
        String body = text(extras.getCharSequence(Notification.EXTRA_BIG_TEXT));
        if (body.isEmpty()) body = text(extras.getCharSequence(Notification.EXTRA_TEXT));
        if (title.isEmpty() && body.isEmpty()) return null;
        String content = title + "\n" + body;
        synchronized (lastContent) {
            if (content.equals(lastContent.get(sbn.getKey()))) return null;
            lastContent.put(sbn.getKey(), content);
        }
        String pkg = sbn.getPackageName();
        PackageManager pm = getPackageManager();
        String app = pkg;
        Drawable icon = null;
        try { app = String.valueOf(pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0))); icon = pm.getApplicationIcon(pkg); }
        catch (PackageManager.NameNotFoundException ignored) { }
        Icon large = n.getLargeIcon();
        if (large != null) {
            try { Drawable d = large.loadDrawable(createPackageContextSafe(pkg)); if (d != null) icon = d; } catch (RuntimeException ignored) { }
        }
        try {
            JSONObject json = new JSONObject();
            json.put("type", "notification");
            json.put("key", sbn.getKey());
            json.put("pkg", pkg);
            json.put("app", app);
            json.put("title", limit(title, 200));
            json.put("text", limit(body, 600));
            json.put("when", sbn.getPostTime());
            if (icon != null) json.put("icon", png(icon));
            return json.toString();
        } catch (org.json.JSONException e) { return null; }
    }

    private android.content.Context createPackageContextSafe(String pkg) {
        try { return createPackageContext(pkg, 0); } catch (PackageManager.NameNotFoundException e) { return this; }
    }

    private static String png(Drawable drawable) {
        Bitmap bitmap = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        drawable.setBounds(0, 0, ICON_PX, ICON_PX);
        drawable.draw(canvas);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
        bitmap.recycle();
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP);
    }

    private void broadcast(String line) {
        byte[] bytes = (line + "\n").getBytes(StandardCharsets.UTF_8);
        for (LocalSocket client : clients) {
            try { synchronized (client) { client.getOutputStream().write(bytes); client.getOutputStream().flush(); } }
            catch (IOException e) { clients.remove(client); close(client); }
        }
    }

    private static String text(CharSequence value) { return value == null ? "" : value.toString().trim(); }
    private static String limit(String value, int max) { return value.length() <= max ? value : value.substring(0, max) + "…"; }
    private static void close(LocalSocket socket) { try { socket.close(); } catch (IOException ignored) { } }
}
