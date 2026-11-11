package kr.blinklabs.blinklink.tests;
import android.app.*;import android.os.*;import kr.blinklabs.blinklink.MacroStore;
/** Read persistence in the signed test APK only; no production export endpoint. */
public final class MacroUxReadout extends Instrumentation {
 @Override public void onCreate(Bundle args){super.onCreate(args);start();}
 @Override public void onStart(){Bundle out=new Bundle();try{String json=MacroStore.exportData(getTargetContext());out.putString("stream","BLINK_DEFS="+android.util.Base64.encodeToString(json.getBytes(java.nio.charset.StandardCharsets.UTF_8),android.util.Base64.NO_WRAP));finish(Activity.RESULT_OK,out);}catch(Exception e){out.putString("stream","ERROR "+e.toString());finish(Activity.RESULT_CANCELED,out);}}
}
