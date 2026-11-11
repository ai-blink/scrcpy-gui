package kr.blinklabs.blinklink;

import android.app.*;
import android.content.*;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.util.*;

/** Native list and full-screen sequence editor, with document-provider import/export. */
public final class MacroActivity extends Activity {
    private LinearLayout body,actionsBox;private TextView status,feedback;private ScrollView scroll;
    private Button monitorButton;private AlertDialog actionEditor;private Spinner actionType;private EditText actionValue;private int actionIndex=-1;
    private int bg,ink,muted,accent,fill;private JSONObject editing;private EditText name,time,wifi;private Spinner trigger;private CheckBox charging,enabled;
    private final Handler h=new Handler(Looper.getMainLooper());private android.window.OnBackInvokedCallback back;
    private final Runnable refresh=new Runnable(){public void run(){refreshStatus();h.postDelayed(this,2000);}};
    private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
    @Override public void onCreate(Bundle s){boolean dark=(getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES;setTheme(dark?android.R.style.Theme_Material_NoActionBar:android.R.style.Theme_Material_Light_NoActionBar);super.onCreate(s);bg=Color.parseColor(dark?"#111820":"#F5F7FA");ink=Color.parseColor(dark?"#E4ECF4":"#16283A");muted=Color.parseColor(dark?"#AFBECC":"#526272");accent=Color.parseColor(dark?"#B7D3F0":"#173D5B");fill=Color.parseColor(dark?"#21384B":"#E2EBF3");
        int bars=WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;getWindow().getDecorView();getWindow().getInsetsController().setSystemBarsAppearance(dark?0:bars,bars);
        if(Build.VERSION.SDK_INT>=33){back=()->leave();getOnBackInvokedDispatcher().registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,back);}
        try{if(s!=null&&s.containsKey("edit")){editing=new JSONObject(s.getString("edit"));editor();if(s.getBoolean("actionOpen",false)){final int at=s.getInt("actionIndex",-1),kind=s.getInt("actionType",0);final String value=s.getString("actionValue","");body.post(()->{if(!isFinishing()&&!isDestroyed()&&editing!=null)actionDialog(at,kind,value);});}}else list();}catch(Exception e){error(e);list();}
    }
    private LinearLayout column(){LinearLayout v=new LinearLayout(this);v.setOrientation(LinearLayout.VERTICAL);return v;}
    private void shell(String title){status=null;monitorButton=null;LinearLayout root=column();root.setBackgroundColor(bg);root.setOnApplyWindowInsetsListener((v,i)->{android.graphics.Insets b=i.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());v.setPadding(b.left,b.top,b.right,b.bottom);return i;});setContentView(root);
        LinearLayout header=column();header.setPadding(dp(24),dp(12),dp(24),dp(8));label(header,title,24,true);root.addView(header);
        scroll=new ScrollView(this);scroll.setFillViewport(true);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));FrameLayout frame=new FrameLayout(this);scroll.addView(frame);body=column();body.setPadding(dp(24),dp(8),dp(24),dp(24));FrameLayout.LayoutParams p=new FrameLayout.LayoutParams(Math.min(getResources().getDisplayMetrics().widthPixels,dp(600)),-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);frame.addView(body,p);
        feedback=label(root,"",16,false);feedback.setPadding(dp(24),dp(10),dp(24),dp(10));feedback.setBackgroundColor(fill);feedback.setVisibility(View.GONE);feedback.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        LinearLayout footer=column();footer.setPadding(dp(24),dp(8),dp(24),dp(8));button(footer,editing==null?"연결 화면으로":"목록으로 돌아가기",editing==null?this::openConnection:this::leave);root.addView(footer);
    }
    private TextView label(LinearLayout p,String text,int size,boolean bold){TextView t=new TextView(this);t.setText(text);t.setTextSize(size);t.setTextColor(bold?ink:muted);t.setLineSpacing(dp(3),1);if(bold)t.setTypeface(null,Typeface.BOLD);p.addView(t,new LinearLayout.LayoutParams(-1,-2));return t;}
    private void gap(LinearLayout p){Space s=new Space(this);p.addView(s,new LinearLayout.LayoutParams(1,dp(12)));}
    private void line(LinearLayout p){gap(p);View v=new View(this);v.setBackgroundColor(muted);p.addView(v,new LinearLayout.LayoutParams(-1,dp(1)));gap(p);}
    private Button button(LinearLayout p,String text,Runnable fn){Button b=new Button(this);b.setText(text);b.setTextSize(18);b.setAllCaps(false);b.setTextColor(accent);b.setStateListAnimator(null);b.setElevation(0);b.setMinHeight(dp(56));b.setPadding(dp(12),dp(10),dp(12),dp(10));GradientDrawable g=new GradientDrawable();g.setColor(fill);g.setCornerRadius(dp(12));b.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x336688AA),g,null));LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.topMargin=dp(8);p.addView(b,lp);b.setOnClickListener(v->fn.run());return b;}
    private void message(String s){feedback.setText(s);feedback.setVisibility(View.VISIBLE);}
    private void error(Exception e){new AlertDialog.Builder(this).setTitle("확인해 주세요").setMessage(e.getMessage()).setPositiveButton("확인",null).show();}
    private void list(){editing=null;shell("내 매크로");status=label(body,"",16,true);refreshStatus();label(body,"자동 실행은 감시 시작 후 동작합니다. 강제 중지·재부팅 후에는 다시 시작하세요.",14,false);
        monitorButton=button(body,"",()->{try{
            boolean shownRunning=Boolean.TRUE.equals(monitorButton.getTag());
            if(shownRunning!=MacroService.running){refreshStatus();message("감시 상태가 바뀌었어요. 표시된 동작을 다시 선택하세요.");return;}
            monitorButton.setEnabled(false);
            if(shownRunning)stopService(new Intent(this,MacroService.class));else MacroService.send(this,"monitor",null);
            h.postDelayed(this::refreshStatus,150);
        }catch(RuntimeException e){refreshStatus();error(e);}});refreshStatus();
        button(body,"새 매크로 만들기",()->{try{editing=MacroStore.fresh();editor();}catch(Exception e){error(e);}});
        line(body);label(body,"기본 매크로 · 무선 연결 복구",20,true);label(body,"등록 Wi-Fi에서 디버깅을 복구합니다. 연결 화면에서 별도로 시작하고 멈춥니다.",16,false);button(body,"기본 연결 복구 열기",this::openConnection);
        JSONArray all=MacroStore.all(this);if(all.length()==0){line(body);label(body,"아직 만든 매크로가 없어요",20,true);label(body,"실행 조건을 고르고 동작을 원하는 순서로 추가하세요.",16,false);}
        for(int i=0;i<all.length();i++){JSONObject m=all.optJSONObject(i);line(body);label(body,m.optString("name"),20,true);label(body,MacroStore.TRIGGERS[m.optInt("trigger")]+(m.optInt("trigger")==1?" · "+m.optString("time"):"")+" → 동작 "+m.optJSONArray("actions").length()+"개",16,false);
            if(m.optBoolean("charging")||!m.optString("wifi").isEmpty())label(body,"추가 조건: "+(m.optBoolean("charging")?"충전 중 ":"")+m.optString("wifi"),14,false);
            Switch on=new Switch(this);on.setText("자동 실행 허용");on.setTextSize(16);on.setTextColor(ink);on.setMinHeight(dp(56));on.setChecked(m.optBoolean("enabled"));body.addView(on);on.setOnCheckedChangeListener((b,value)->{try{m.put("enabled",value);MacroStore.save(this,m);message(value?"자동 실행을 허용했어요. 조건 감시도 시작하세요.":"자동 실행을 껐어요.");}catch(Exception e){error(e);}});
            button(body,"실행 · "+m.optString("name"),()->{try{MacroService.send(this,"run",m.optString("id"));message("실행 요청을 보냈어요. 실행 기록에서 결과를 확인하세요.");}catch(RuntimeException e){error(e);}});
            button(body,"편집 · "+m.optString("name"),()->{try{editing=new JSONObject(m.toString());editor();}catch(Exception e){error(e);}});
            button(body,"복제 · "+m.optString("name"),()->{try{JSONObject clone=new JSONObject(m.toString());clone.put("id",UUID.randomUUID().toString()).put("name",MacroStore.copyName(m.optString("name"))).put("enabled",false);MacroStore.save(this,clone);list();message("꺼진 상태로 복제했어요.");}catch(Exception e){error(e);}});
        }
        line(body);button(body,"매크로 내보내기",()->document(true));button(body,"매크로 가져오기",()->document(false));button(body,"매크로 실행 기록",this::history);
    }
    private void refreshStatus(){boolean watching=MacroService.running;if(status!=null)status.setText(watching?"조건 감시 중":"조건 감시 중지 · 자동 재시작 안 함");if(monitorButton!=null){monitorButton.setText(watching?"조건 감시 중지":"조건 감시 시작");monitorButton.setTag(watching);monitorButton.setEnabled(true);}}
    private void openConnection(){startActivity(new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP));finish();}
    private EditText input(LinearLayout p,String title,String value){label(p,title,16,true);EditText e=new EditText(this);e.setText(value);e.setTextSize(16);e.setTextColor(ink);e.setMinHeight(dp(56));e.setContentDescription(title);p.addView(e,new LinearLayout.LayoutParams(-1,-2));gap(p);return e;}
    private void editor(){shell("매크로 편집");name=input(body,"매크로 이름",editing.optString("name"));label(body,"언제 실행할까요?",20,true);trigger=new Spinner(this);trigger.setAdapter(new ArrayAdapter<String>(this,android.R.layout.simple_spinner_dropdown_item,MacroStore.TRIGGERS));trigger.setSelection(editing.optInt("trigger"));trigger.setMinimumHeight(dp(56));body.addView(trigger,new LinearLayout.LayoutParams(-1,-2));gap(body);
        LinearLayout timeGroup=column();body.addView(timeGroup);time=input(timeGroup,"지정 시각 (HH:mm)",editing.optString("time","09:00"));
        trigger.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){public void onItemSelected(AdapterView<?> p,View v,int at,long id){timeGroup.setVisibility(at==1?View.VISIBLE:View.GONE);}public void onNothingSelected(AdapterView<?> p){}});time.setInputType(android.text.InputType.TYPE_CLASS_DATETIME|android.text.InputType.TYPE_DATETIME_VARIATION_TIME);
        label(body,"추가 조건 · 모두 맞을 때 실행",20,true);charging=new CheckBox(this);charging.setText("충전 중에만");charging.setTextColor(ink);charging.setTextSize(16);charging.setMinHeight(dp(56));charging.setChecked(editing.optBoolean("charging"));body.addView(charging);wifi=input(body,"Wi-Fi 이름 (비우면 제한 없음)",editing.optString("wifi"));
        label(body,"Wi-Fi 실행·조건에는 설정 화면의 위치 권한이 필요합니다. 시각 감시는 약 15초 간격이며 절전 중 지연될 수 있습니다.",14,false);line(body);label(body,"무엇을 할까요?",20,true);label(body,"위에서 아래 순서대로 실행합니다. 앱 열기는 알림을 눌러야 열립니다. 한 동작이 실패하면 남은 동작을 멈춥니다.",14,false);actionsBox=column();body.addView(actionsBox);renderActions();button(body,"동작 추가",()->actionDialog(-1));
        line(body);enabled=new CheckBox(this);enabled.setText("저장 후 자동 실행 허용");enabled.setMinHeight(dp(56));enabled.setTextColor(ink);enabled.setChecked(editing.optBoolean("enabled"));body.addView(enabled);
        button(body,"매크로 저장",()->{try{collect();MacroStore.save(this,editing);list();message("저장했어요. 자동 실행하려면 조건 감시를 시작하세요.");}catch(Exception e){error(e);}});
        if(MacroStore.find(this,editing.optString("id"))!=null)button(body,"이 매크로 삭제",()->new AlertDialog.Builder(this).setTitle("매크로를 삭제할까요?").setMessage(editing.optString("name")).setNegativeButton("취소",null).setPositiveButton("삭제",(d,w)->{try{MacroStore.remove(this,editing.optString("id"));list();}catch(Exception e){error(e);}}).show());
    }
    private void collect()throws JSONException{editing.put("name",name.getText().toString().trim()).put("trigger",trigger.getSelectedItemPosition()).put("time",time.getText().toString().trim()).put("charging",charging.isChecked()).put("wifi",wifi.getText().toString().trim()).put("enabled",enabled.isChecked());}
    private void renderActions(){actionsBox.removeAllViews();JSONArray a=editing.optJSONArray("actions");if(a.length()==0)label(actionsBox,"동작을 하나 이상 추가하세요.",16,false);for(int i=0;i<a.length();i++){final int at=i;JSONObject s=a.optJSONObject(i);gap(actionsBox);label(actionsBox,(i+1)+". "+MacroStore.ACTIONS[s.optInt("type")],18,true);if(!s.optString("value").isEmpty())label(actionsBox,s.optString("value"),16,false);button(actionsBox,(i+1)+"번 동작 수정",()->actionDialog(at));LinearLayout row=new LinearLayout(this);actionsBox.addView(row);small(row,"위로",()->move(at,-1),i>0);small(row,"아래로",()->move(at,1),i<a.length()-1);small(row,"삭제",()->{a.remove(at);renderActions();},true);}}
    private void small(LinearLayout row,String text,Runnable r,boolean allowed){LinearLayout cell=column();row.addView(cell,new LinearLayout.LayoutParams(0,-2,1));Button b=button(cell,text,r);b.setEnabled(allowed);}
    private void move(int at,int delta){try{JSONArray a=editing.getJSONArray("actions");Object s=a.get(at);a.put(at,a.get(at+delta));a.put(at+delta,s);renderActions();}catch(Exception e){error(e);}}
    private void actionDialog(int at){actionDialog(at,-1,null);}
    private void actionDialog(int at,int restoredType,String restoredValue){JSONArray a=editing.optJSONArray("actions");if(at<0&&a.length()>=16){message("동작은 최대 16개입니다.");return;}JSONObject old=at>=0?a.optJSONObject(at):null;LinearLayout fields=column();fields.setPadding(dp(20),dp(8),dp(20),dp(8));Spinner type=new Spinner(this);type.setAdapter(new ArrayAdapter<String>(this,android.R.layout.simple_spinner_dropdown_item,MacroStore.ACTIONS));type.setMinimumHeight(dp(56));type.setSelection(restoredType>=0?restoredType:old==null?0:old.optInt("type"));fields.addView(type);EditText value=input(fields,"내용 / 값",restoredValue!=null?restoredValue:old==null?"":old.optString("value"));label(fields,"알림·읽기: 내용 / 대기: 0~30초 / 앱: 패키지 이름 / 음량: 0~100 / 진동: 0~3000ms / 복구: 값 없음",14,false);
        ScrollView viewport=new ScrollView(this);viewport.addView(fields);
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle("동작 설정").setView(viewport).setNegativeButton("취소",null).setPositiveButton("추가 / 적용",null).create();actionEditor=dialog;actionType=type;actionValue=value;actionIndex=at;dialog.setOnDismissListener(d->{if(actionEditor==dialog){actionEditor=null;actionType=null;actionValue=null;actionIndex=-1;}});dialog.setOnShowListener(d->dialog.getButton(-1).setOnClickListener(v->{try{JSONObject s=new JSONObject().put("type",type.getSelectedItemPosition()).put("value",value.getText().toString());JSONObject test=MacroStore.fresh().put("name","검사").put("actions",new JSONArray().put(s));MacroStore.validate(test);if(at<0)a.put(s);else a.put(at,s);renderActions();dialog.dismiss();}catch(Exception e){value.setError(e.getMessage());}}));dialog.show();
    }
    private void history(){new AlertDialog.Builder(this).setTitle("매크로 실행 기록").setMessage(MacroStore.prefs(this).getString("log","아직 실행 기록이 없어요.")).setPositiveButton("확인",null).show();}
    private void leave(){if(editing==null){finish();return;}new AlertDialog.Builder(this).setTitle("편집을 마칠까요?").setMessage("저장하지 않은 변경은 사라집니다.").setNegativeButton("계속 편집",null).setPositiveButton("목록으로",(d,w)->list()).show();}
    @SuppressWarnings("deprecation") @Override public void onBackPressed(){leave();}
    private void document(boolean out){Intent i=new Intent(out?Intent.ACTION_CREATE_DOCUMENT:Intent.ACTION_OPEN_DOCUMENT).setType("application/json").addCategory(Intent.CATEGORY_OPENABLE);if(out)i.putExtra(Intent.EXTRA_TITLE,"blink-macros.json");try{startActivityForResult(i,out?40:41);}catch(ActivityNotFoundException e){error(e);}}
    @Override protected void onActivityResult(int req,int result,Intent data){super.onActivityResult(req,result,data);if(result!=RESULT_OK||data==null||data.getData()==null)return;try{if(req==40){try(OutputStream o=getContentResolver().openOutputStream(data.getData(),"wt")){if(o==null)throw new IOException("파일을 열 수 없습니다");o.write(MacroStore.exportData(this).getBytes(java.nio.charset.StandardCharsets.UTF_8));}message("내보냈어요.");}else if(req==41){ByteArrayOutputStream out=new ByteArrayOutputStream();try(InputStream in=getContentResolver().openInputStream(data.getData())){if(in==null)throw new IOException("파일을 열 수 없습니다");byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1){out.write(b,0,n);if(out.size()>MacroStore.MAX_BACKUP_BYTES)throw new IOException("가져오기 파일 크기 제한을 초과했습니다.");}}String json=new String(out.toByteArray(),java.nio.charset.StandardCharsets.UTF_8);new AlertDialog.Builder(this).setTitle("매크로를 가져올까요?").setMessage("현재 목록에 추가합니다. 가져온 매크로는 모두 꺼진 상태로 저장됩니다.").setNegativeButton("취소",null).setPositiveButton("가져오기",(d,w)->{try{int count=MacroStore.importData(this,json);list();message(count+"개를 가져왔어요. 내용을 확인한 뒤 켜세요.");}catch(Exception e){error(e);}}).show();}}catch(Exception e){error(e);}}
    @Override public void onResume(){super.onResume();h.post(refresh);}
    @Override public void onPause(){h.removeCallbacks(refresh);super.onPause();}
    @Override public void onDestroy(){h.removeCallbacksAndMessages(null);if(actionEditor!=null)actionEditor.dismiss();super.onDestroy();}
    @Override protected void onSaveInstanceState(Bundle s){if(editing!=null)try{collect();s.putString("edit",editing.toString());if(actionEditor!=null&&actionEditor.isShowing()){s.putBoolean("actionOpen",true);s.putInt("actionIndex",actionIndex);s.putInt("actionType",actionType.getSelectedItemPosition());s.putString("actionValue",actionValue.getText().toString());}}catch(JSONException ignored){}super.onSaveInstanceState(s);}
}
