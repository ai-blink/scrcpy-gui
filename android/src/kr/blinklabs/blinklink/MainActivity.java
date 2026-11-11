package kr.blinklabs.blinklink;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.*;
import android.location.LocationManager;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.widget.*;

/** Native, task-first UI. Monitoring and retry behavior stay in LinkService/LinkState. */
public final class MainActivity extends Activity {
    private static final int CONNECTION=0, SETUP=1, HISTORY=2;
    private static final String COMMAND="adb -s <기기주소:포트> shell pm grant kr.blinklabs.blinklink android.permission.WRITE_SECURE_SETTINGS";
    private LinearLayout content, pcHelp, accessHelp;
    private ScrollView scroll;
    private TextView headline, guidance, monitorValue, wifiValue, feedback, log, preparation;
    private final TextView[] stepStatus=new TextView[3];
    private Button recover, toggle, helpToggle, accessToggle;
    private final Button[] tabs=new Button[3];
    private final int[] scrollPositions=new int[3];
    private int page=CONNECTION;
    private boolean pcHelpExpanded;
    private boolean accessHelpExpanded;
    private boolean backRegistered;
    private android.window.OnBackInvokedCallback backCallback;
    private Palette colors;
    private String feedbackMessage="";
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final Runnable refresh=new Runnable(){public void run(){update();handler.postDelayed(this,2000);}};
    private final Runnable hideFeedback=()->{feedbackMessage="";updateFeedback();};

    private static final class Palette {
        final int surface, ink, muted, primary, onPrimary, tonal, outline, success, warning, error;
        Palette(boolean dark) {
            surface=Color.parseColor(dark?"#111820":"#F5F7FA");
            ink=Color.parseColor(dark?"#E4ECF4":"#16283A");
            muted=Color.parseColor(dark?"#AFBECC":"#526272");
            primary=Color.parseColor(dark?"#B7D3F0":"#173D5B");
            onPrimary=Color.parseColor(dark?"#133149":"#FFFFFF");
            tonal=Color.parseColor(dark?"#21384B":"#E2EBF3");
            outline=Color.parseColor(dark?"#718294":"#798796");
            success=Color.parseColor(dark?"#9FD8BB":"#145C46");
            warning=Color.parseColor(dark?"#EBC38B":"#855215");
            error=Color.parseColor(dark?"#FFB4B8":"#9B3138");
        }
    }
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
    @Override public void onCreate(Bundle saved) {
        boolean dark=(getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES;
        setTheme(dark?android.R.style.Theme_Material_NoActionBar:android.R.style.Theme_Material_Light_NoActionBar);
        super.onCreate(saved);
        colors=new Palette(dark);
        accessHelpExpanded=!locationReady();
        if(saved!=null){page=saved.getInt("page",CONNECTION);pcHelpExpanded=saved.getBoolean("help");accessHelpExpanded=saved.getBoolean("accessHelp");int[] positions=saved.getIntArray("scroll");if(positions!=null)System.arraycopy(positions,0,scrollPositions,0,Math.min(3,positions.length));}
        LinearLayout root=vertical();root.setBackgroundColor(colors.surface);setContentView(root);
        root.setOnApplyWindowInsetsListener((v,insets)->{android.graphics.Insets b=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());v.setPadding(b.left,b.top,b.right,b.bottom);return insets;});
        int appearance=WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
        getWindow().getInsetsController().setSystemBarsAppearance(dark?0:appearance,appearance);
        LinearLayout bar=vertical();bar.setPadding(dp(24),dp(12),dp(24),dp(12));
        TextView brand=text(bar,"Blink Link",22,true,colors.ink);brand.setAccessibilityHeading(true);root.addView(bar);
        scroll=new ScrollView(this);scroll.setFillViewport(true);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        FrameLayout frame=new FrameLayout(this);scroll.addView(frame);
        content=vertical();content.setPadding(dp(24),dp(8),dp(24),dp(24));
        FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(Math.min(getResources().getDisplayMetrics().widthPixels,dp(600)),-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);frame.addView(content,cp);
        feedback=text(root,"",16,false,colors.primary);feedback.setPadding(dp(24),dp(12),dp(24),dp(12));feedback.setBackgroundColor(colors.tonal);feedback.setVisibility(View.GONE);feedback.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        divider(root);
        LinearLayout navigation=new LinearLayout(this);navigation.setOrientation(LinearLayout.HORIZONTAL);navigation.setPadding(dp(16),dp(8),dp(16),dp(8));
        String[] names={"연결","설정","기록"};
        for(int i=0;i<3;i++){final int destination=i;Button tab=makeButton(names[i],false,false,()->showPage(destination));tab.setMinHeight(dp(56));tab.setPadding(dp(8),dp(12),dp(8),dp(12));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,-2,1);p.setMargins(dp(4),0,dp(4),0);navigation.addView(tab,p);tabs[i]=tab;}
        root.addView(navigation);
        if(Build.VERSION.SDK_INT>=33)backCallback=()->showPage(CONNECTION);
        buildPage();update();
    }
    private LinearLayout vertical(){LinearLayout v=new LinearLayout(this);v.setOrientation(LinearLayout.VERTICAL);return v;}
    private void showPage(int destination){
        if(destination==page)return;
        scrollPositions[page]=scroll.getScrollY();page=destination;feedbackMessage="";buildPage();update();
    }
    private void buildPage(){
        content.removeAllViews();headline=null;guidance=null;monitorValue=null;wifiValue=null;log=null;preparation=null;recover=null;toggle=null;
        java.util.Arrays.fill(stepStatus,null);
        for(int i=0;i<3;i++){tabs[i].setSelected(i==page);tabs[i].setStateDescription(i==page?"선택됨":"");tabs[i].setTextColor(i==page?colors.primary:colors.muted);tabs[i].setBackground(buttonBackground(i==page?colors.tonal:colors.surface,0));}
        if(page==CONNECTION)buildConnection();else if(page==SETUP)buildSetup();else buildHistory();
        if(Build.VERSION.SDK_INT>=33){if(page!=CONNECTION&&!backRegistered){getOnBackInvokedDispatcher().registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,backCallback);backRegistered=true;}else if(page==CONNECTION&&backRegistered){getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(backCallback);backRegistered=false;}}
        scroll.post(()->scroll.scrollTo(0,scrollPositions[page]));
    }
    private void buildConnection(){
        headline=text(content,"",28,true,colors.ink);headline.setAccessibilityHeading(true);
        gap(content,8);guidance=text(content,"",16,false,colors.muted);
        gap(content,24);monitorValue=detailRow("자동 복구");gap(content,16);wifiValue=detailRow("현재 Wi-Fi");
        gap(content,24);
        recover=button(content,"지금 한 번 복구",true,false,()->{
            if(!manualPrepared()){showPage(SETUP);return;}
            if(!LinkState.wifi(this)||!LinkState.trusted(this).equals(LinkState.ssid(this))){say("등록한 Wi-Fi에 연결한 뒤 다시 눌러주세요.");return;}
            if(LinkState.adb(this)){say("무선 디버깅은 이미 켜져 있어요. PC에서 연결을 확인하세요.");return;}
            LinkState.setAdb(this,true);say("복구를 요청했어요. Android 허용 창이 나타나면 확인하세요.");update();
        });
        gap(content,12);toggle=button(content,"자동 복구 시작",false,false,this::toggleMonitoring);
        gap(content,24);text(content,"등록된 Wi-Fi에서만 자동으로 켭니다.",14,false,colors.muted);
    }
    private TextView detailRow(String label){
        LinearLayout row=vertical();text(row,label,14,false,colors.muted);gap(row,4);TextView value=text(row,"",18,true,colors.ink);content.addView(row);return value;
    }
    private void buildSetup(){
        heading("처음 한 번 설정");preparation=text(content,"",16,false,colors.muted);gap(content,24);
        stepStatus[0]=step("1. Wi-Fi 확인 권한");
        text(content,"Wi-Fi 이름을 구분하는 데 사용합니다. 위치 좌표를 저장하거나 전송하지 않습니다.",16,false,colors.muted);
        gap(content,12);accessToggle=button(content,"권한 설정 방법",false,false,()->{accessHelpExpanded=!accessHelpExpanded;syncAccess();});
        accessHelp=vertical();gap(accessHelp,12);button(accessHelp,"위치 · 알림 권한 허용",false,false,this::requestAccess);
        gap(accessHelp,8);button(accessHelp,"항상 허용으로 설정",false,false,()->openAppSettings());
        gap(accessHelp,8);button(accessHelp,"위치 설정 열기",false,false,()->open(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)));
        gap(accessHelp,8);text(accessHelp,"앱 권한 → 위치 → 정확한 위치와 '항상 허용'을 선택하세요.",14,false,colors.muted);
        content.addView(accessHelp);syncAccess();
        sectionBreak();stepStatus[1]=step("2. 사용할 Wi-Fi");
        text(content,"집처럼 본인이 관리하는 Wi-Fi에 연결한 뒤 등록하세요.",16,false,colors.muted);
        gap(content,12);button(content,"현재 Wi-Fi 등록",false,false,this::registerWifi);
        sectionBreak();stepStatus[2]=step("3. PC 연결 권한");
        text(content,"PC와 한 번 페어링하고 연결 복구 권한을 부여합니다.",16,false,colors.muted);
        gap(content,12);helpToggle=button(content,"PC 설정 방법",false,false,()->{pcHelpExpanded=!pcHelpExpanded;syncHelp();});
        pcHelp=vertical();gap(pcHelp,12);
        text(pcHelp,"휴대폰의 개발자 옵션 → 무선 디버깅 → 페어링 코드로 기기 페어링을 열고, PC의 scrcpy-gui에서 페어링하세요.",16,false,colors.muted);
        gap(pcHelp,12);button(pcHelp,"개발자 옵션 · 페어링 열기",false,false,()->open(new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)));
        gap(pcHelp,12);text(pcHelp,"페어링 후 PC에서 아래 명령을 실행하세요. <기기주소:포트>는 연결된 휴대폰의 값으로 바꿉니다.",16,false,colors.muted);
        gap(pcHelp,12);TextView command=text(pcHelp,COMMAND,14,false,colors.ink);command.setTypeface(Typeface.MONOSPACE);command.setTextIsSelectable(true);
        gap(pcHelp,12);button(pcHelp,"권한 명령 복사",false,false,()->copy(COMMAND,"권한 명령을 복사했어요."));
        gap(pcHelp,12);text(pcHelp,"Android 허용 창에서 본인의 Wi-Fi를 확인하세요. 이후에도 시스템 허용이나 잠금 해제가 필요할 수 있습니다.",14,false,colors.muted);
        content.addView(pcHelp);syncHelp();
        gap(content,24);button(content,"연결 화면으로",true,false,()->showPage(CONNECTION));
        sectionBreak();text(content,"추가 설정",20,true,colors.ink);gap(content,8);
        text(content,"감시가 자주 중단되면 삼성 앱 배터리 설정의 '제한 없음'을 확인하세요.",16,false,colors.muted);
        gap(content,12);button(content,"앱 권한 · 배터리 설정",false,false,this::openAppSettings);
        gap(content,16);button(content,"디버깅 끄고 복구 정지",false,true,()->new AlertDialog.Builder(this).setTitle("PC 연결을 종료할까요?").setMessage("무선 디버깅과 자동 복구를 끕니다. 연결 중인 PC 화면이 끊길 수 있습니다.").setPositiveButton("끄기",(d,w)->{LinkState.pause(this);LinkState.setAdb(this,false);say("자동 복구를 멈추고 디버깅 끄기를 요청했어요.");update();}).setNegativeButton("취소",null).show());
    }
    private TextView step(String title){text(content,title,20,true,colors.ink);gap(content,4);TextView status=text(content,"",14,true,colors.muted);gap(content,8);return status;}
    private void syncHelp(){pcHelp.setVisibility(pcHelpExpanded?View.VISIBLE:View.GONE);helpToggle.setText(pcHelpExpanded?"PC 설정 방법 닫기":"PC 설정 방법");helpToggle.setStateDescription(pcHelpExpanded?"펼쳐짐":"접힘");}
    private void syncAccess(){accessHelp.setVisibility(accessHelpExpanded?View.VISIBLE:View.GONE);accessToggle.setText(accessHelpExpanded?"권한 설정 방법 닫기":"권한 설정 방법");accessToggle.setStateDescription(accessHelpExpanded?"펼쳐짐":"접힘");}
    private void buildHistory(){
        heading("최근 동작");text(content,"이 휴대폰에만 보관되는 연결 복구 기록입니다.",16,false,colors.muted);gap(content,16);
        button(content,"기록 복사",false,false,()->copy(LinkState.prefs(this).getString("log",""),"기록을 복사했어요."));gap(content,12);
        gap(content,12);log=text(content,"",16,false,colors.ink);log.setTextIsSelectable(true);
    }
    private void toggleMonitoring(){
        if(LinkService.isRunning()){LinkState.pause(this);say("자동 복구를 쉬고 있어요. 현재 디버깅 상태는 유지됩니다.");update();return;}
        if(!prepared()){showPage(SETUP);return;}
        new AlertDialog.Builder(this).setTitle("자동 복구를 시작할까요?").setMessage("등록한 Wi-Fi에서 무선 디버깅을 켭니다. 페어링한 PC가 접근할 수 있으며 언제든 일시정지할 수 있습니다.")
            .setPositiveButton("시작",(d,w)->{LinkState.startExplicitly(this);feedbackMessage="";update();}).setNegativeButton("취소",null).show();
    }
    private void registerWifi(){
        String ssid=LinkState.ssid(this);
        if(!LinkState.wifi(this)||ssid.isEmpty()){say("Wi-Fi 이름을 확인할 수 없어요. Wi-Fi 연결, 위치 권한과 위치 켜짐을 확인하세요.");return;}
        new AlertDialog.Builder(this).setTitle("이 Wi-Fi를 등록할까요?").setMessage(ssid+"\n본인이 관리하는 네트워크인지 확인하세요. 같은 이름의 네트워크를 구분하지는 못합니다.")
            .setPositiveButton("등록",(d,w)->{LinkState.prefs(this).edit().putString("trusted",ssid).apply();LinkState.log(this,"사용할 Wi-Fi 등록 완료");say("사용할 Wi-Fi를 등록했어요.");update();}).setNegativeButton("취소",null).show();
    }
    private void requestAccess(){
        if(Build.VERSION.SDK_INT>=33)requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION,Manifest.permission.POST_NOTIFICATIONS},10);
        else requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION},10);
    }
    private boolean locationReady(){return LinkState.backgroundReady(this)&&getSystemService(LocationManager.class).isLocationEnabled();}
    private boolean prepared(){return locationReady()&&!LinkState.trusted(this).isEmpty()&&LinkState.permission(this);}
    private boolean manualPrepared(){return !LinkState.trusted(this).isEmpty()&&LinkState.permission(this);}
    private void openAppSettings(){open(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:"+getPackageName())));}
    private void open(Intent i){try{startActivity(i);}catch(ActivityNotFoundException e){say("이 설정의 바로가기를 지원하지 않아요. 휴대폰 설정에서 직접 열어주세요.");}}
    private void copy(String value,String message){if(value.isEmpty()){say("아직 복사할 기록이 없어요.");return;}getSystemService(ClipboardManager.class).setPrimaryClip(ClipData.newPlainText("Blink Link",value));say(message);}
    private void say(String message){feedbackMessage=message;updateFeedback();handler.removeCallbacks(hideFeedback);int timeout=getSystemService(android.view.accessibility.AccessibilityManager.class).getRecommendedTimeoutMillis(10000,android.view.accessibility.AccessibilityManager.FLAG_CONTENT_TEXT);handler.postDelayed(hideFeedback,timeout);}
    private void updateFeedback(){if(feedback!=null){if(!feedback.getText().toString().equals(feedbackMessage))feedback.setText(feedbackMessage);feedback.setVisibility(feedbackMessage.isEmpty()?View.GONE:View.VISIBLE);}}
    private void update(){
        boolean running=LinkService.isRunning(),on=LinkState.adb(this),ready=prepared();String current=LinkState.ssid(this),trusted=LinkState.trusted(this);
        if(page==CONNECTION){
            headline.setText(!ready?(manualPrepared()?"자동 복구 설정이 필요해요":"처음 설정이 필요해요"):on?"무선 디버깅 켜짐":running?"연결 복구 대기 중":"무선 디버깅 꺼짐");
            headline.setTextColor(ready&&on?colors.success:colors.ink);
            String message=!ready?"권한과 사용할 Wi-Fi를 준비하세요.":current.isEmpty()?"Wi-Fi 이름을 확인할 수 없어요. 위치 설정을 확인하세요.":!trusted.equals(current)?"등록된 Wi-Fi에서만 복구할 수 있어요.":on?"PC의 scrcpy에서 연결을 확인하세요.":running?"등록한 Wi-Fi에서 연결을 다시 준비합니다.":"자동 복구를 시작하거나 한 번만 복구할 수 있어요.";
            if(ready&&running&&!on&&trusted.equals(current)&&LinkState.prefs(this).getString("status","").startsWith("재시도 대기"))message="자동 요청을 잠시 쉬고 있어요. 아래에서 직접 복구할 수 있어요.";
            guidance.setText(message);
            monitorValue.setText(running?"감시 중":LinkState.enabled(this)?"감시 중단 · 다시 시작 필요":"일시정지");monitorValue.setTextColor(running?colors.success:colors.warning);
            wifiValue.setText(current.isEmpty()?"확인할 수 없음":current);recover.setText(manualPrepared()?"지금 한 번 복구":"설정 이어하기");
            toggle.setText(running?"자동 복구 일시정지":LinkState.enabled(this)?"감시 다시 시작":"자동 복구 시작");
        }else if(page==SETUP){
            boolean[] done={locationReady(),!trusted.isEmpty(),LinkState.permission(this)};int count=0;
            for(int i=0;i<3;i++){if(done[i])count++;stepStatus[i].setText(done[i]?(i==1?"등록됨 · "+trusted:"준비됨"):(i==0?"정확한 위치 · 항상 허용 · 위치 켜짐 필요":"설정 필요"));stepStatus[i].setTextColor(done[i]?colors.success:colors.warning);}
            preparation.setText(count==3?"준비가 끝났어요. 연결 화면에서 시작하세요.":"3단계 중 "+count+"단계 준비됨");
        }else if(log!=null&&!log.hasSelection()){
            String value=LinkState.prefs(this).getString("log","");if(value.isEmpty())value="아직 동작 기록이 없어요.\n연결 화면에서 복구를 실행하면 여기에 표시됩니다.";
            if(!log.getText().toString().equals(value))log.setText(value);
        }
        updateFeedback();
    }
    private void heading(String value){TextView h=text(content,value,24,true,colors.ink);h.setAccessibilityHeading(true);gap(content,8);}
    private void sectionBreak(){gap(content,24);divider(content);gap(content,24);}
    private void divider(LinearLayout parent){View line=new View(this);line.setBackgroundColor(colors.outline);parent.addView(line,new LinearLayout.LayoutParams(-1,dp(1)));}
    private void gap(LinearLayout parent,int size){View v=new View(this);v.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);parent.addView(v,new LinearLayout.LayoutParams(1,dp(size)));}
    private TextView text(LinearLayout parent,String value,int sp,boolean bold,int color){TextView t=new TextView(this);t.setText(value);t.setTextSize(sp);t.setTextColor(color);t.setLineSpacing(dp(3),1f);if(bold)t.setTypeface(null,Typeface.BOLD);parent.addView(t,new LinearLayout.LayoutParams(-1,-2));return t;}
    private GradientDrawable shape(int fill,int stroke){GradientDrawable d=new GradientDrawable();d.setColor(fill);d.setCornerRadius(dp(12));if(stroke!=0)d.setStroke(dp(1),stroke);return d;}
    private android.graphics.drawable.Drawable buttonBackground(int fill,int border){
        int highlight=fill==colors.primary?colors.onPrimary:colors.primary;
        StateListDrawable states=new StateListDrawable();GradientDrawable focused=shape(fill,highlight);focused.setStroke(dp(2),highlight);
        states.addState(new int[]{android.R.attr.state_focused},focused);states.addState(new int[]{android.R.attr.state_hovered},shape(fill,highlight));states.addState(new int[]{},shape(fill,border));
        return new RippleDrawable(ColorStateList.valueOf((highlight&0x00ffffff)|0x26000000),states,shape(Color.WHITE,0));
    }
    private Button makeButton(String label,boolean primary,boolean danger,Runnable action){Button b=new Button(this);b.setText(label);b.setTextSize(18);b.setAllCaps(false);b.setMinHeight(dp(64));b.setPadding(dp(16),dp(14),dp(16),dp(14));b.setGravity(Gravity.CENTER);b.setTextColor(danger?colors.error:primary?colors.onPrimary:colors.primary);b.setBackground(buttonBackground(primary?colors.primary:colors.surface,danger?colors.error:primary?0:colors.outline));b.setStateListAnimator(null);b.setOnClickListener(v->action.run());return b;}
    private Button button(LinearLayout parent,String label,boolean primary,boolean danger,Runnable action){Button b=makeButton(label,primary,danger,action);parent.addView(b,new LinearLayout.LayoutParams(-1,-2));return b;}
    @Override protected void onSaveInstanceState(Bundle state){scrollPositions[page]=scroll.getScrollY();state.putInt("page",page);state.putBoolean("help",pcHelpExpanded);state.putBoolean("accessHelp",accessHelpExpanded);state.putIntArray("scroll",scrollPositions);super.onSaveInstanceState(state);}
    @SuppressWarnings("deprecation") @Override public void onBackPressed(){if(page!=CONNECTION)showPage(CONNECTION);else super.onBackPressed();}
    @Override public void onResume(){super.onResume();handler.post(refresh);}
    @Override public void onPause(){handler.removeCallbacks(refresh);super.onPause();}
    @Override public void onDestroy(){handler.removeCallbacksAndMessages(null);super.onDestroy();}
}
