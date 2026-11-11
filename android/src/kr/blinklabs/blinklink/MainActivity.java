package kr.blinklabs.blinklink;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.widget.*;

public final class MainActivity extends Activity {
    private LinearLayout column;
    private TextView status, log;
    private Button toggle;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable refresh = new Runnable() { public void run() { update(); handler.postDelayed(this, 2000); } };
    private int dp(int value) { return (int)(value * getResources().getDisplayMetrics().density + .5f); }
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true); scroll.setBackgroundColor(Color.rgb(244,247,250));
        column = new LinearLayout(this); column.setOrientation(LinearLayout.VERTICAL); column.setPadding(dp(24),dp(24),dp(24),dp(24)); scroll.addView(column);
        setContentView(scroll);
        getWindow().getInsetsController().setSystemBarsAppearance(WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS, WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
        scroll.setOnApplyWindowInsetsListener((v, insets) -> { android.graphics.Insets b = insets.getInsets(WindowInsets.Type.systemBars()); v.setPadding(b.left,b.top,b.right,b.bottom); return insets; });
        text("Blink Link", 32, true);
        text("휴대폰을 다시 잡지 않아도\nPC 연결을 준비합니다.", 21, false);
        status = text("상태 확인 중", 18, true);
        toggle = button("자동 복구 시작", () -> {
            if (LinkService.isRunning()) { pause(); return; }
            if (!LinkState.permission(this) || LinkState.trusted(this).isEmpty() || !LinkState.backgroundReady(this)) { dialog("준비가 필요합니다", "PC 권한, 사용할 Wi-Fi 등록, 정확한 위치 및 위치 '항상 허용'을 확인하세요."); return; }
            new AlertDialog.Builder(this).setTitle("자동 복구를 시작할까요?")
                .setMessage("등록 Wi-Fi에서 무선 디버깅을 켭니다. 기존에 페어링한 PC가 접근할 수 있습니다. 알림에서 언제든 일시정지할 수 있습니다. 재부팅 후 첫 잠금 해제 뒤 감시를 재개합니다.")
                .setPositiveButton("시작", (d,w) -> { LinkState.startExplicitly(this); update(); }).setNegativeButton("취소",null).show();
        });
        button("지금 한 번 복구", () -> {
            if (!LinkState.wifi(this) || LinkState.trusted(this).isEmpty() || !LinkState.trusted(this).equals(LinkState.ssid(this))) {
                dialog("등록 Wi-Fi를 확인하세요", "등록한 Wi-Fi가 연결되고 이름이 확인될 때만 켤 수 있습니다."); return;
            }
            if (!LinkState.adb(this)) LinkState.setAdb(this,true); update();
        });
        button("디버깅 끄고 복구 정지", () -> new AlertDialog.Builder(this).setTitle("PC 연결이 끊길 수 있습니다")
            .setMessage("무선 디버깅과 자동 복구를 모두 끕니다.").setPositiveButton("끄기",(d,w)->{pause(); LinkState.setAdb(this,false); update();}).setNegativeButton("취소",null).show());
        text("처음 한 번 준비", 24, true);
        text("1. 위치 권한을 허용하고 Android 위치를 켜세요. Wi-Fi 이름을 구분할 때만 사용하며 위치를 저장하거나 전송하지 않습니다.", 17, false);
        button("위치 · 알림 권한 허용", () -> {
            if (Build.VERSION.SDK_INT >= 33) requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION,Manifest.permission.POST_NOTIFICATIONS},10);
            else requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION},10);
        });
        button("위치 설정 열기", () -> open(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)));
        button("앱 권한 · 배터리 설정", () -> open(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:"+getPackageName()))));
        text("백그라운드 복구에는 앱 권한 → 위치 → '항상 허용'이 필요합니다. 삼성 설정에서 배터리를 '제한 없음'으로 설정하면 감시 중단을 줄일 수 있습니다.",16,false);
        button("현재 Wi-Fi 등록", () -> {
            String s = LinkState.ssid(this);
            if (!LinkState.wifi(this) || s.isEmpty()) { dialog("Wi-Fi 이름을 확인할 수 없습니다", "Wi-Fi 연결, 정확한 위치 권한, Android 위치 켜짐을 확인하세요."); return; }
            new AlertDialog.Builder(this).setTitle("이 Wi-Fi에서 자동 복구").setMessage(s + "\n본인이 관리하는 네트워크인지 확인하세요. 같은 이름의 네트워크를 암호학적으로 구분하지는 못합니다.")
                .setPositiveButton("등록",(d,w)->{LinkState.prefs(this).edit().putString("trusted",s).apply(); LinkState.log(this,"사용할 Wi-Fi 등록 완료");update();}).setNegativeButton("취소",null).show();
        });
        text("2. PC에서 최초 권한을 부여하세요. PC와 한 번 페어링한 뒤 아래 명령을 실행합니다.",17,false);
        TextView cmd=text("adb -s <기기주소:포트> shell pm grant kr.blinklabs.blinklink android.permission.WRITE_SECURE_SETTINGS",15,false); cmd.setTextIsSelectable(true);
        button("권한 명령 복사", () -> { getSystemService(ClipboardManager.class).setPrimaryClip(ClipData.newPlainText("ADB 권한", "adb -s <기기주소:포트> shell pm grant kr.blinklabs.blinklink android.permission.WRITE_SECURE_SETTINGS")); Toast.makeText(this,"복사했습니다",Toast.LENGTH_SHORT).show(); });
        button("개발자 옵션 · 페어링 열기", () -> open(new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)));
        text("3. Android의 무선 디버깅 허용 창에서 현재 Wi-Fi를 허용하세요. 페어링과 잠금 해제는 Android 확인이 필요합니다. 이 앱은 PC 연결 성공을 판정하지 않습니다.",17,false);
        text("최근 동작",24,true); log=text("",14,false); log.setTextIsSelectable(true);
    }
    private void pause() { LinkState.pause(this); update(); }
    private void open(Intent i) { try { startActivity(i); } catch (ActivityNotFoundException e) { dialog("직접 설정을 열어주세요","이 기기에서는 해당 설정 바로가기를 지원하지 않습니다."); } }
    private void dialog(String title,String body) { new AlertDialog.Builder(this).setTitle(title).setMessage(body).setPositiveButton("확인",null).show(); }
    private TextView text(String s,int size,boolean bold) { TextView t=new TextView(this);t.setText(s);t.setTextSize(size);t.setTextColor(Color.rgb(22,40,58));t.setPadding(0,dp(10),0,dp(10));if(bold)t.setTypeface(null,1);column.addView(t);return t; }
    private Button button(String s,Runnable r) { Button b=new Button(this);b.setText(s);b.setTextSize(18);b.setAllCaps(false);b.setMinHeight(dp(64)); LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.setMargins(0,dp(6),0,dp(6));column.addView(b,p);b.setOnClickListener(v->r.run());return b; }
    private void update() {
        String trusted=LinkState.trusted(this), current=LinkState.ssid(this);
        String bg=checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION)==PackageManager.PERMISSION_GRANTED?"허용":"항상 허용 필요";
        status.setText("자동 복구  " + (LinkService.isRunning()?"감시 중":LinkState.enabled(this)?"감시 중단 · 다시 시작 필요":"일시정지") + "\nPC 권한  " + (LinkState.permission(this)?"준비됨":"최초 부여 필요") + "\n무선 디버깅  " + (LinkState.adb(this)?"켜짐":"꺼짐") + "\n등록 Wi-Fi  " + (trusted.isEmpty()?"미등록":trusted) + "\n현재 Wi-Fi  " + (current.isEmpty()?"확인 불가":current) + "\n백그라운드 위치  " + bg + "\n\n" + LinkState.prefs(this).getString("status","아래 준비 단계를 완료하세요."));
        toggle.setText(LinkService.isRunning()?"자동 복구 일시정지":LinkState.enabled(this)?"감시 다시 시작":"자동 복구 시작"); log.setText(LinkState.prefs(this).getString("log","아직 동작 기록이 없습니다."));
    }
    @Override public void onResume(){super.onResume();handler.post(refresh);}
    @Override public void onPause(){handler.removeCallbacks(refresh);super.onPause();}
}
