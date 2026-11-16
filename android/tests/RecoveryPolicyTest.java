import kr.blinklabs.blinklink.RecoveryPolicy;
import static kr.blinklabs.blinklink.RecoveryPolicy.Decision.*;
public final class RecoveryPolicyTest {
    private static int count;
    private static void check(RecoveryPolicy.Decision want, boolean enabled, boolean permission, boolean wifi, String trusted, String current, boolean on) {
        RecoveryPolicy.Decision got=RecoveryPolicy.decide(enabled,permission,wifi,trusted,current,on);
        if(got!=want)throw new AssertionError("Expected "+want+" but got "+got);
        count++;
    }
    private static void expect(boolean ok, String what) { if(!ok)throw new AssertionError(what); count++; }
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
        check(ENABLE,true,true,true,"home_5G\nhome_2G","home_2G",false);
        check(ALREADY_ON,true,true,true,"home_5G\nhome_2G","home_5G",true);
        check(OTHER_WIFI,true,true,true,"home_5G\nhome_2G","home",false);
        check(OTHER_WIFI,true,true,true,"home_5G\nhome_2G","home_5G\nhome_2G",false);
        // Membership used directly by MacroService (wireless-recover step) as well as decide().
        expect(RecoveryPolicy.contains("home_5G\nhome_2G","home_2G"),"contains second registered Wi-Fi");
        expect(RecoveryPolicy.contains("home","home"),"contains legacy single value");
        expect(!RecoveryPolicy.contains("home_5G\nhome_2G","home"),"partial name is not trusted");
        expect(!RecoveryPolicy.contains("Free\nBar","Free\nBar"),"newline name never matches");
        expect(!RecoveryPolicy.validSsid("Free\n같은 공유기"),"newline SSID rejected");
        expect(!RecoveryPolicy.validSsid("tab\tname"),"control char rejected");
        expect(RecoveryPolicy.validSsid("우리집 Wi-Fi"),"Korean SSID accepted");
        System.out.println("PASS: "+count+" recovery policy cases");
    }
}
