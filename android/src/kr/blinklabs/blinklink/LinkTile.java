package kr.blinklabs.blinklink;
import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;
import android.service.quicksettings.*;
public final class LinkTile extends TileService {
    @Override public void onStartListening() {
        Tile t = getQsTile();
        if (t != null) { t.setState(LinkService.isRunning() ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE); t.setSubtitle(LinkService.isRunning() ? "감시 중" : LinkState.enabled(this) ? "다시 시작 필요" : "설정 열기"); t.updateTile(); }
    }
    @SuppressWarnings("deprecation") @Override public void onClick() {
        Intent i = new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (Build.VERSION.SDK_INT >= 34) startActivityAndCollapse(PendingIntent.getActivity(this, 2, i, PendingIntent.FLAG_IMMUTABLE));
        else startActivityAndCollapse(i);
    }
}
