package kr.blinklabs.blinklink;

import java.util.*;
import java.util.function.Consumer;

/** Owns utterance completion and timeout by unique execution identity. Main-thread only. */
public final class SpeechSessions {
    public interface Scheduler { void after(Runnable task,long delay); void cancel(Runnable task); }
    private final Scheduler scheduler;
    private final Map<String,Pending> pending=new HashMap<>();
    private static final class Pending {
        Runnable timeout,done;Consumer<String> failed;
    }
    public SpeechSessions(Scheduler scheduler){this.scheduler=scheduler;}
    public String begin(Runnable done,Consumer<String> failed){
        String token=UUID.randomUUID().toString();Pending p=new Pending();p.done=done;p.failed=failed;
        p.timeout=()->fail(token,"음성 읽기 시간 초과");pending.put(token,p);scheduler.after(p.timeout,60000);return token;
    }
    public void done(String token){Pending p=take(token);if(p!=null)p.done.run();}
    public void fail(String token,String reason){Pending p=take(token);if(p!=null)p.failed.accept(reason);}
    public void cancel(String token){take(token);}
    private Pending take(String token){Pending p=pending.remove(token);if(p!=null)scheduler.cancel(p.timeout);return p;}
    public void clear(){for(String token:new ArrayList<>(pending.keySet()))cancel(token);}
}
