import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
// Mirrors AtomicReference's exact mechanism: a reference VarHandle bound via
// findVarHandle in <clinit>, then signature-polymorphic get/set/compareAndSet/
// getAndSet ops. Each ref op carries fastjavac's RC store barrier → heap-balanced.
public class VarHandleCas {
    private volatile Object ref;
    private static final VarHandle REF;
    static {
        try {
            REF = MethodHandles.lookup().findVarHandle(VarHandleCas.class, "ref", Object.class);
        } catch (ReflectiveOperationException e) { throw new RuntimeException("vh"); }
    }
    static class Box { int v; Box(int v){ this.v = v; } }
    public static void main(String[] a) {
        VarHandleCas t = new VarHandleCas();
        Box b1 = new Box(11), b2 = new Box(22);
        REF.set(t, b1);
        System.out.println(((Box) REF.get(t)).v);                       // 11
        System.out.println(REF.compareAndSet(t, b1, b2) ? 1 : 0);        // 1
        System.out.println(((Box) REF.get(t)).v);                       // 22
        System.out.println(REF.compareAndSet(t, b1, b2) ? 1 : 0);        // 0
        Box old = (Box) REF.getAndSet(t, b1);
        System.out.println(old.v);                                      // 22
        System.out.println(((Box) REF.get(t)).v);                       // 11
    }
}
