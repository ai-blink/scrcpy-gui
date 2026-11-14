package kr.blinklabs.blinklink;

import android.app.job.*;

/** Restarts the user-enabled monitor after Android kills the process (permission change, memory). */
public final class LinkWatchdog extends JobService {
    @Override public boolean onStartJob(JobParameters p) {
        if (!LinkState.enabled(this)) { LinkState.cancelWatchdog(this); return false; }
        // A user stop stays a stop; the user restarts from the app.
        if (!LinkService.isRunning() && !LinkState.userStopped(this)) {
            LinkState.log(this, "감시가 멈춰 있어 다시 시작합니다.");
            LinkState.start(this);
        }
        return false;
    }
    @Override public boolean onStopJob(JobParameters p) { return false; }
}
