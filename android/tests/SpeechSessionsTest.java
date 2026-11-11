import kr.blinklabs.blinklink.SpeechSessions;
import java.util.*;
public final class SpeechSessionsTest {
 static int count;static void ok(boolean v){if(!v)throw new AssertionError();count++;}
 public static void main(String[] args){List<Runnable> timers=new ArrayList<>();Set<Runnable> cancelled=new HashSet<>();SpeechSessions s=new SpeechSessions(new SpeechSessions.Scheduler(){public void after(Runnable r,long ms){timers.add(r);}public void cancel(Runnable r){cancelled.add(r);}});int[] done={0},failed={0};
 String a=s.begin(()->done[0]++,reason->failed[0]++);Runnable old=timers.get(0);s.done(a);ok(done[0]==1&&cancelled.contains(old));
 String b=s.begin(()->done[0]++,reason->failed[0]++);ok(!a.equals(b));old.run();s.fail(a,"late error");s.done(a);ok(done[0]==1&&failed[0]==0);s.done(b);ok(done[0]==2&&failed[0]==0);
 String c=s.begin(()->done[0]++,reason->failed[0]++);Runnable timeout=timers.get(2);timeout.run();s.done(c);timeout.run();ok(done[0]==2&&failed[0]==1&&cancelled.contains(timeout));
 String d=s.begin(()->done[0]++,reason->failed[0]++);s.cancel(d);timers.get(3).run();s.done(d);ok(done[0]==2&&failed[0]==1);
 String e=s.begin(()->done[0]++,reason->failed[0]++);s.clear();timers.get(4).run();s.fail(e,"late");ok(done[0]==2&&failed[0]==1);
 String f=s.begin(()->done[0]++,reason->failed[0]++);s.fail(f,"engine error");s.done(f);ok(failed[0]==2&&done[0]==2);System.out.println("PASS: "+count+" speech session regression cases");
 }
}
