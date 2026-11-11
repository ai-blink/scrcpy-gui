import kr.blinklabs.blinklink.RecoveryPolicy;
import static kr.blinklabs.blinklink.RecoveryPolicy.Decision.*;
public final class RecoveryPolicyTest {
    private static int count;
    private static void check(RecoveryPolicy.Decision want, boolean enabled, boolean permission, boolean wifi, String trusted, String current, boolean on) {
        RecoveryPolicy.Decision got=RecoveryPolicy.decide(enabled,permission,wifi,trusted,current,on);
        if(got!=want)throw new AssertionError("Expected "+want+" but got "+got);
        count++;
    }
    public static void main(String[] args) {
        check(PAUSED,false,true,true,"home","home",false);
        check(PERMISSION,true,false,true,"home","home",false);
        check(WIFI,true,true,false,"home","home",false);
        check(IDENTITY,true,true,true,"","home",false);
        check(IDENTITY,true,true,true,"home","",false);
        check(IDENTITY,true,true,true,"home",null,false);
        check(OTHER_WIFI,true,true,true,"home","cafe",false);
        check(OTHER_WIFI,true,true,true,"home","HOME",true);
        check(ALREADY_ON,true,true,true,"home","home",true);
        check(ENABLE,true,true,true,"home","home",false);
        System.out.println("PASS: "+count+" recovery policy cases");
    }
}
