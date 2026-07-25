// jdk.internal.misc.Unsafe reference-family accessors — the RC-critical part of
// the native concurrency layer. get/put/compareAndSet/getAndSetReference each
// carry fastjavac's reference-count store barrier (retain new / release old)
// around the atomic pointer op, so the 0-live-heap oracle stays balanced. This
// is the primitive VarHandle-based AtomicReference would bottom out in.
// Compile with: --add-exports java.base/jdk.internal.misc=ALL-UNNAMED
import jdk.internal.misc.Unsafe;
public class UnsafeRef {
    private Object ref;
    static class Box { int v; Box(int v){ this.v = v; } }
    public static void main(String[] a) {
        Unsafe U = Unsafe.getUnsafe();
        long off = U.objectFieldOffset(UnsafeRef.class, "ref");
        UnsafeRef holder = new UnsafeRef();
        Box b1 = new Box(11), b2 = new Box(22);
        U.putReference(holder, off, b1);
        System.out.println(((Box) U.getReference(holder, off)).v);                 // 11
        System.out.println(U.compareAndSetReference(holder, off, b1, b2) ? 1 : 0); // 1
        System.out.println(((Box) U.getReference(holder, off)).v);                 // 22
        System.out.println(U.compareAndSetReference(holder, off, b1, b2) ? 1 : 0); // 0
        Box old = (Box) U.getAndSetReference(holder, off, b1);
        System.out.println(old.v);                                                 // 22
        System.out.println(((Box) U.getReference(holder, off)).v);                 // 11
    }
}
