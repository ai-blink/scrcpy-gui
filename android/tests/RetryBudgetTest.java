import kr.blinklabs.blinklink.RetryBudget;
public final class RetryBudgetTest {
    private static int count;
    private static void expect(boolean value) { if (!value) throw new AssertionError("Case " + (count+1)); count++; }
    public static void main(String[] args) {
        RetryBudget b = new RetryBudget("");
        expect(b.take(10000));
        expect(!b.take(10001));
        expect(b.take(40000));
        expect(b.take(70000));
        // Transient ON observations cannot mutate the independent budget.
        expect(!b.take(100000));
        b = new RetryBudget(b.save()); // Service restart must retain the window.
        expect(!b.take(120000));
        expect(!b.take(309999));
        expect(b.take(310000));
        expect(!b.take(315000)); // Still two requests within the rolling window.
        expect(b.take(340000));
        expect(b.take(370000));
        expect(!b.take(400000));
        // New device boot uses a fresh budget, not previous uptime values.
        expect(new RetryBudget("").take(0));
        expect(new RetryBudget("10,40,70").save().equals("10,40,70"));
        System.out.println("PASS: " + count + " retry budget cases");
    }
}
