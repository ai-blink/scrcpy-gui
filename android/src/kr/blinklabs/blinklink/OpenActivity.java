package kr.blinklabs.blinklink;

import android.app.Activity;
import android.app.ActivityOptions;
import android.app.PendingIntent;
import android.os.Build;

/**
 * Invisible trampoline started on the PC app window's display. Android blocks background services
 * from opening another app's notification screen, but allows it from a visible activity.
 */
public final class OpenActivity extends Activity {
    static final String TARGET = "target", REQUEST = "request";
    private boolean sent;

    @SuppressWarnings("deprecation")
    @Override protected void onResume() {
        super.onResume();
        if (sent) return;
        sent = true;
        getWindow().getDecorView().post(() -> {
            PendingIntent target = getIntent().getParcelableExtra(TARGET);
            String error = "";
            if (target == null) error = "열 화면 정보가 없음";
            else {
                ActivityOptions options = ActivityOptions.makeBasic().setLaunchDisplayId(getDisplay().getDisplayId());
                if (Build.VERSION.SDK_INT >= 36) options.setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_ALWAYS);
                else if (Build.VERSION.SDK_INT >= 34) options.setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED);
                try { target.send(this, 0, null, null, null, null, options.toBundle()); }
                catch (PendingIntent.CanceledException e) { error = "앱이 이 알림의 화면을 더 이상 열어 주지 않음(이미 열었거나 앱이 취소함)"; }
                catch (RuntimeException e) { error = "알림 화면 열기 실패 · " + e.getMessage(); }
                if (!error.isEmpty()) LinkState.log(this, error);
            }
            NotifyListener.opened(getIntent().getStringExtra(REQUEST), error);
            finish();
            overridePendingTransition(0, 0);
        });
    }
}
