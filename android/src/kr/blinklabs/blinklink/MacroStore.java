package kr.blinklabs.blinklink;

import android.content.*;
import org.json.*;
import java.util.*;

/** Versioned local macro definitions. Imported definitions are always disabled. */
public final class MacroStore {
    public static final String[] TRIGGERS={"수동 실행","매일 지정 시각","충전 시작","충전 종료","Wi-Fi 연결","화면 켜짐","잠금 해제"};
    public static final String[] ACTIONS={"알림 표시","텍스트 읽기","기다리기 (초)","앱 열기 (패키지 이름)","미디어 음량 (0~100)","진동 (밀리초)","무선 디버깅 복구"};
    public static SharedPreferences prefs(Context c){return c.getSharedPreferences("macros",0);}
    public static JSONArray all(Context c){try{return new JSONArray(prefs(c).getString("definitions","[]"));}catch(JSONException e){throw new IllegalStateException("저장된 매크로를 읽을 수 없습니다",e);}}
    public static JSONObject find(Context c,String id){JSONArray a=all(c);for(int i=0;i<a.length();i++)if(a.optJSONObject(i).optString("id").equals(id))return a.optJSONObject(i);return null;}
    public static void save(Context c,JSONObject m)throws JSONException{validate(m);JSONArray a=all(c),out=new JSONArray();boolean found=false;for(int i=0;i<a.length();i++){JSONObject old=a.getJSONObject(i);if(old.getString("id").equals(m.getString("id"))){out.put(m);found=true;}else out.put(old);}if(!found)out.put(m);if(out.length()>100)throw new JSONException("매크로는 최대 100개입니다");write(c,out);}
    public static void remove(Context c,String id)throws JSONException{JSONArray a=all(c),out=new JSONArray();for(int i=0;i<a.length();i++)if(!a.getJSONObject(i).getString("id").equals(id))out.put(a.get(i));write(c,out);}
    private static void write(Context c,JSONArray a)throws JSONException{if(!prefs(c).edit().putString("definitions",a.toString()).commit())throw new JSONException("저장 실패");}
    public static JSONObject fresh()throws JSONException{return new JSONObject().put("id",UUID.randomUUID().toString()).put("name","").put("enabled",false).put("trigger",0).put("time","09:00").put("charging",false).put("wifi","").put("actions",new JSONArray());}
    public static void validate(JSONObject m)throws JSONException{
        if(m.getString("id").isEmpty()||m.getString("name").trim().isEmpty()||m.getString("name").length()>80)throw new JSONException("이름은 1~80자로 입력하세요");
        int t=m.getInt("trigger");if(t<0||t>=TRIGGERS.length)throw new JSONException("지원하지 않는 실행 조건");
        if(!m.getString("time").matches("(?:[01][0-9]|2[0-3]):[0-5][0-9]"))throw new JSONException("시각은 HH:mm 형식입니다");
        m.getBoolean("enabled");m.getBoolean("charging");if(m.getString("wifi").length()>64)throw new JSONException("Wi-Fi 이름이 너무 깁니다");
        JSONArray a=m.getJSONArray("actions");if(a.length()<1||a.length()>16)throw new JSONException("동작은 1~16개입니다");int waits=0;
        for(int i=0;i<a.length();i++){JSONObject s=a.getJSONObject(i);int k=s.getInt("type");String v=s.getString("value");if(k<0||k>=ACTIONS.length||v.length()>1000)throw new JSONException("지원하지 않는 동작 또는 너무 긴 값");
            if((k==0||k==1)&&v.trim().isEmpty())throw new JSONException("알림·읽기 내용을 입력하세요");
            if(k==3&&!v.matches("[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)+"))throw new JSONException("앱 패키지 이름을 확인하세요");
            if(k==2||k==4||k==5){int n;try{n=Integer.parseInt(v);}catch(NumberFormatException e){throw new JSONException("숫자를 입력하세요");}int max=k==2?30:k==4?100:3000;if(n<0||n>max)throw new JSONException("허용 범위: 0~"+max);if(k==2)waits+=n;}
        }if(waits>120)throw new JSONException("총 대기는 120초 이내입니다");
    }
    public static String exportData(Context c)throws JSONException{return new JSONObject().put("version",1).put("macros",all(c)).toString(2);}
    public static int importData(Context c,String data)throws JSONException{
        if(data.length()>262144)throw new JSONException("파일은 256KB 이내입니다");JSONObject root=new JSONObject(data);if(root.getInt("version")!=1)throw new JSONException("지원하지 않는 파일 버전");
        JSONArray incoming=root.getJSONArray("macros"),out=all(c);if(out.length()+incoming.length()>100)throw new JSONException("합계 100개를 초과합니다");
        for(int i=0;i<incoming.length();i++){JSONObject m=new JSONObject(incoming.getJSONObject(i).toString());m.put("id",UUID.randomUUID().toString()).put("enabled",false);validate(m);out.put(m);}write(c,out);return incoming.length();
    }
    public static void log(Context c,String s){String old=prefs(c).getString("log","");String v=new java.text.SimpleDateFormat("MM-dd HH:mm:ss",Locale.KOREA).format(new Date())+"  "+s+"\n"+old;prefs(c).edit().putString("log",v.substring(0,Math.min(v.length(),12000))).apply();}
}
