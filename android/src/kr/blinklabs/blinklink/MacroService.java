package kr.blinklabs.blinklink;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.media.AudioManager;
import android.os.*;
import android.speech.tts.*;
import org.json.*;
import java.util.*;

/** User-started monitoring; no automatic restart after process/user stop. */
public final class MacroService extends Service {
    public static volatile boolean running;
    private final Handler h=new Handler(Looper.getMainLooper());
    private final Map<String,Run> active=new HashMap<>();
    private final Map<String,Long> lastAutomatic=new HashMap<>();
    private boolean monitoring,charging;private String wifi="";private int nextNotice=100;
    private TextToSpeech tts;private int speechState;private final Map<String,Runnable> speechDone=new HashMap<>();
    private final Runnable tick=new Runnable(){public void run(){if(monitoring){poll();h.postDelayed(this,15000);}}};
    public static void send(Context c,String action,String id){Intent i=new Intent(c,MacroService.class).setAction(action);if(id!=null)i.putExtra("id",id);c.startForegroundService(i);}
    private final BroadcastReceiver events=new BroadcastReceiver(){public void onReceive(Context c,Intent i){if(!monitoring)return;String a=i.getAction();if(Intent.ACTION_POWER_CONNECTED.equals(a)||Intent.ACTION_POWER_DISCONNECTED.equals(a))poll();else if(Intent.ACTION_SCREEN_ON.equals(a))fire(5);else if(Intent.ACTION_USER_PRESENT.equals(a))fire(6);}};
    @Override public void onCreate(){super.onCreate();NotificationManager nm=getSystemService(NotificationManager.class);nm.createNotificationChannel(new NotificationChannel("macros","매크로 실행",NotificationManager.IMPORTANCE_DEFAULT));nm.createNotificationChannel(new NotificationChannel("macro-watch","매크로 감시",NotificationManager.IMPORTANCE_LOW));
        PendingIntent open=PendingIntent.getActivity(this,20,new Intent(this,MacroActivity.class),PendingIntent.FLAG_IMMUTABLE);
        PendingIntent stop=PendingIntent.getService(this,21,new Intent(this,MacroService.class).setAction("stop"),PendingIntent.FLAG_IMMUTABLE);
        Notification n=new Notification.Builder(this,"macro-watch").setSmallIcon(android.R.drawable.ic_menu_manage).setContentTitle("Blink Link · 매크로 실행 중").setContentText("조건 감시 또는 동작 실행 · 중지 가능").setContentIntent(open).setOngoing(true).addAction(new Notification.Action.Builder(null,"전체 중지",stop).build()).build();
        if(Build.VERSION.SDK_INT>=34)startForeground(20,n,ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);else startForeground(20,n);
        IntentFilter f=new IntentFilter();for(String a:new String[]{Intent.ACTION_POWER_CONNECTED,Intent.ACTION_POWER_DISCONNECTED,Intent.ACTION_SCREEN_ON,Intent.ACTION_USER_PRESENT})f.addAction(a);if(Build.VERSION.SDK_INT>=33)registerReceiver(events,f,Context.RECEIVER_NOT_EXPORTED);else registerReceiver(events,f);
        charging=isCharging();wifi=LinkState.wifi(this)?LinkState.ssid(this):"";
    }
    @Override public int onStartCommand(Intent i,int flags,int id){String a=i==null?"stop":i.getAction();if("stop".equals(a)){stopSelf();return START_NOT_STICKY;}
        if("monitor".equals(a)){monitoring=true;running=true;h.removeCallbacks(tick);h.post(tick);MacroStore.log(this,"조건 감시 시작");}
        else if("run".equals(a)){JSONObject m=MacroStore.find(this,i.getStringExtra("id"));if(m!=null)execute(m,true);idle();}return START_NOT_STICKY;
    }
    private boolean isCharging(){Intent b=registerReceiver(null,new IntentFilter(Intent.ACTION_BATTERY_CHANGED));return b!=null&&b.getIntExtra(BatteryManager.EXTRA_PLUGGED,0)!=0;}
    private void poll(){boolean c=isCharging();String w=LinkState.wifi(this)?LinkState.ssid(this):"";if(c!=charging){charging=c;fire(c?2:3);}if(!w.equals(wifi)){wifi=w;if(!w.isEmpty())fire(4);}fire(1);}
    private boolean constraints(JSONObject m){return (!m.optBoolean("charging")||isCharging())&&(m.optString("wifi").isEmpty()||m.optString("wifi").equals(LinkState.ssid(this)));}
    private void fire(int trigger){JSONArray list=MacroStore.all(this);String now=new java.text.SimpleDateFormat("HH:mm",Locale.US).format(new Date());String day=new java.text.SimpleDateFormat("yyyy-MM-dd",Locale.US).format(new Date());
        for(int x=0;x<list.length();x++){JSONObject m=list.optJSONObject(x);if(!m.optBoolean("enabled")||m.optInt("trigger")!=trigger||!constraints(m))continue;
            if(trigger==1){String key="fired."+m.optString("id");if(!now.equals(m.optString("time"))||day.equals(MacroStore.prefs(this).getString(key,"")))continue;if(!MacroStore.prefs(this).edit().putString(key,day).commit())continue;}
            execute(m,false);
        }
    }
    private void execute(JSONObject m,boolean manual){String id=m.optString("id");
        long now=SystemClock.elapsedRealtime();if(!manual&&now-lastAutomatic.getOrDefault(id,-5000L)<5000)return;if(active.containsKey(id)){MacroStore.log(this,m.optString("name")+" · 기존 실행 중, 중복 생략");return;}if(active.size()>=4){MacroStore.log(this,"동시 실행 4개 초과 · 요청 생략");return;}
        try{MacroStore.validate(m);}catch(JSONException e){MacroStore.log(this,"정의 오류: "+e.getMessage());return;}
        if(!constraints(m)){MacroStore.log(this,m.optString("name")+" · 추가 조건 불일치");return;}if(!manual)lastAutomatic.put(id,now);Run r=new Run(m,manual);active.put(id,r);MacroStore.log(this,r.name+" · 시작");r.next();
    }
    private final class Run{
        final JSONObject m;final String id,name;final boolean manual;final long started=SystemClock.elapsedRealtime();int index;boolean finished;
        Run(JSONObject m,boolean manual){this.m=m;this.manual=manual;id=m.optString("id");name=m.optString("name");}
        void finish(String state){if(finished)return;finished=true;active.remove(id);MacroStore.log(MacroService.this,name+" · "+state);idle();}
        void next(){if(finished)return;JSONObject current=MacroStore.find(MacroService.this,id);if(current==null||(!manual&&!current.optBoolean("enabled"))){finish("취소됨");return;}if(SystemClock.elapsedRealtime()-started>180000){finish("시간 제한 종료");return;}
            JSONArray a=m.optJSONArray("actions");if(index>=a.length()){finish("완료");return;}JSONObject step=a.optJSONObject(index++);int kind=step.optInt("type");String value=step.optString("value");
            try{switch(kind){
                case 0:notice(name,value,null);break;
                case 1:speak(value,()->{if(!finished)next();},this);return;
                case 2:h.postDelayed(this::next,Integer.parseInt(value)*1000L);return;
                case 3:Intent launch=getPackageManager().getLaunchIntentForPackage(value);if(launch==null)throw new IllegalStateException("실행 가능한 앱이 없습니다: "+value);notice(name,"앱을 열려면 누르세요",launch);MacroStore.log(MacroService.this,name+" · 앱 열기 알림 전달 (탭 필요)");break;
                case 4:AudioManager am=getSystemService(AudioManager.class);int max=am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);am.setStreamVolume(AudioManager.STREAM_MUSIC,Math.round(max*Integer.parseInt(value)/100f),0);break;
                case 5:int ms=Integer.parseInt(value);Vibrator v=getSystemService(Vibrator.class);if(!v.hasVibrator())throw new IllegalStateException("진동 장치 없음");if(ms>0)v.vibrate(VibrationEffect.createOneShot(ms,VibrationEffect.DEFAULT_AMPLITUDE));break;
                case 6:if(!LinkState.permission(MacroService.this)||LinkState.trusted(MacroService.this).isEmpty()||!LinkState.wifi(MacroService.this)||!LinkState.trusted(MacroService.this).equals(LinkState.ssid(MacroService.this)))throw new IllegalStateException("PC 권한과 등록 Wi-Fi 연결 필요");if(!LinkState.adb(MacroService.this)){if(!LinkState.takeAutomaticRequest(MacroService.this))throw new IllegalStateException("복구 요청 횟수 제한 중");if(!LinkState.setAdb(MacroService.this,true))throw new IllegalStateException("Android 설정 요청 거절");}MacroStore.log(MacroService.this,name+" · 디버깅 켜기 요청 처리, PC 연결은 별도 확인");break;
                default:throw new IllegalStateException("지원하지 않는 동작");
            }h.post(this::next);}catch(RuntimeException e){finish("실패: "+e.getMessage());}
        }
    }
    private void notice(String title,String text,Intent target){if(!getSystemService(NotificationManager.class).areNotificationsEnabled())throw new IllegalStateException("알림 권한이 꺼져 있습니다");int id=nextNotice++;Notification.Builder b=new Notification.Builder(this,"macros").setSmallIcon(android.R.drawable.ic_menu_info_details).setContentTitle(title).setContentText(text).setStyle(new Notification.BigTextStyle().bigText(text)).setAutoCancel(true);if(target!=null)b.setContentIntent(PendingIntent.getActivity(this,id,target,PendingIntent.FLAG_IMMUTABLE));getSystemService(NotificationManager.class).notify(id,b.build());}
    private void speak(String value,Runnable done,Run run){
        if(tts==null){speechState=0;tts=new TextToSpeech(this,status->{speechState=status==TextToSpeech.SUCCESS?1:-1;});tts.setOnUtteranceProgressListener(new UtteranceProgressListener(){public void onStart(String id){}public void onDone(String id){h.post(()->completeSpeech(id));}public void onError(String id){h.post(()->{speechDone.remove(id);Run r=active.get(id.split(":")[0]);if(r!=null)r.finish("음성 읽기 실패");});}});}
        long deadline=SystemClock.elapsedRealtime()+8000;Runnable ready=new Runnable(){public void run(){if(run.finished)return;if(speechState==0&&SystemClock.elapsedRealtime()<deadline){h.postDelayed(this,100);return;}if(speechState!=1){run.finish("음성 엔진 준비 실패");return;}String token=run.id+":"+run.index;speechDone.put(token,done);if(tts.speak(value,TextToSpeech.QUEUE_ADD,null,token)==TextToSpeech.ERROR){speechDone.remove(token);run.finish("음성 읽기 요청 실패");return;}h.postDelayed(()->{if(speechDone.remove(token)!=null)run.finish("음성 읽기 시간 초과");},60000);}};h.post(ready);
    }
    private void completeSpeech(String id){Runnable r=speechDone.remove(id);if(r!=null)r.run();}
    private void idle(){if(!monitoring&&active.isEmpty())stopSelf();}
    @Override public void onDestroy(){running=false;monitoring=false;h.removeCallbacksAndMessages(null);for(Run r:new ArrayList<>(active.values()))r.finish("중지됨");speechDone.clear();if(tts!=null)tts.shutdown();unregisterReceiver(events);MacroStore.log(this,"매크로 감시·실행 중지");super.onDestroy();}
    @Override public IBinder onBind(Intent i){return null;}
}
