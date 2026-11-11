package kr.blinklabs.blinklink.tests;

import android.content.Context;
import android.content.SharedPreferences;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import kr.blinklabs.blinklink.MacroStore;

/** Called inside the guarded emulator instrumentation runner; restores definitions. */
public final class StoreReviewChecks {
    private static void require(boolean condition,String message){if(!condition)throw new AssertionError(message);}
    private static String repeat(String value,int count){StringBuilder b=new StringBuilder(value.length()*count);for(int i=0;i<count;i++)b.append(value);return b.toString();}
    private static JSONObject definition(String name,String text)throws JSONException{
        JSONArray actions=new JSONArray();
        for(int i=0;i<16;i++)actions.put(new JSONObject().put("type",0).put("value",text));
        return MacroStore.fresh().put("name",name).put("enabled",true).put("actions",actions);
    }
    private static void fixture(SharedPreferences p,JSONArray a){require(p.edit().putString("definitions",a.toString()).commit(),"fixture persistence failed");}

    public static int run(Context c)throws Exception{
        SharedPreferences p=MacroStore.prefs(c);
        String original=p.getString("definitions","[]");
        int count=0;
        try{
            JSONArray six=new JSONArray();
            for(int i=0;i<6;i++)six.put(definition("Korean "+i,repeat("가",1000)));
            fixture(p,six);
            String exported=MacroStore.exportData(c);
            require(exported.getBytes(StandardCharsets.UTF_8).length>262144,"regression fixture must exceed old byte cap");count++;
            fixture(p,new JSONArray());
            require(MacroStore.importData(c,exported)==6&&MacroStore.all(c).length()==6,"large Korean backup roundtrip");count++;
            JSONArray imported=MacroStore.all(c);
            for(int i=0;i<imported.length();i++)require(!imported.getJSONObject(i).getBoolean("enabled")&&!imported.getJSONObject(i).getString("id").equals(six.getJSONObject(i).getString("id")),"restored definitions must be disabled with fresh identities");
            count++;

            String before=p.getString("definitions","");
            String oversized=repeat("가",MacroStore.MAX_BACKUP_BYTES/3+1);
            require(oversized.length()<MacroStore.MAX_BACKUP_BYTES,"UTF-8 fixture must distinguish bytes from characters");count++;
            try{MacroStore.importData(c,oversized);throw new AssertionError("oversized UTF-8 backup accepted");}catch(JSONException expected){}
            require(before.equals(p.getString("definitions","")),"oversized import must preserve existing definitions");count++;

            JSONArray maximum=new JSONArray();
            // A JSON control character expands to six ASCII bytes; final X keeps text nonblank.
            String escaped=repeat("\u0001",999)+"X";
            for(int i=0;i<100;i++)maximum.put(definition(repeat("N",80),escaped));
            fixture(p,maximum);
            String worst=MacroStore.exportData(c);
            int bytes=worst.getBytes(StandardCharsets.UTF_8).length;
            require(bytes>9000000&&bytes<MacroStore.MAX_BACKUP_BYTES,"maximum supported escaped schema fits shared backup limit");count++;
            fixture(p,new JSONArray());
            require(MacroStore.importData(c,worst)==100&&MacroStore.all(c).length()==100,"maximum schema export restores into empty installation");count++;

            String copied=MacroStore.copyName(repeat("N",80));
            require(copied.length()==80&&copied.endsWith(" 복사"),"80-unit source name remains duplicable");count++;
            String unicode=MacroStore.copyName(repeat("N",76)+"\uD83D\uDE00NN");
            require(unicode.equals(repeat("N",76)+" 복사"),"copy truncation must not split surrogate pair");count++;
            MacroStore.validate(definition(copied,"text"));
            MacroStore.validate(definition(unicode,"text"));
            count++;
            return count;
        }finally{
            require(p.edit().putString("definitions",original).commit(),"definition restore failed");
        }
    }
}
