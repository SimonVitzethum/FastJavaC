// Phase 3 mixin target: value() returns 10 until a mixin overwrites it at compile
// time (--weave ValueMixin:WeaveBase), after which it returns 20 — woven natively.
public class WeaveBase {
    int base;
    WeaveBase(int b) { this.base = b; }
    int value() { return 10; }

    public static void main(String[] args) {
        WeaveBase b = new WeaveBase(5);
        int v = b.value();
        if (v != 20) throw new RuntimeException("mixin not woven: " + v);
        System.out.println(v);
    }
}
