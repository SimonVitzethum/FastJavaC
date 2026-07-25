// jdk.internal.misc.Unsafe int-family against fastjavac's object model — the
// native concurrency layer. getUnsafe() lowers to a null receiver;
// objectFieldOffset(Class,String) folds to the real byte offset of the field in
// the compiled struct ({refcount,vtable,fields…}); get/put/compareAndSet/
// getAndAdd/getAndSet become atomic accesses at (base+offset). This is exactly
// how java.util.concurrent.atomic.AtomicInteger drives its state.
// Compile with: --add-exports java.base/jdk.internal.misc=ALL-UNNAMED
import jdk.internal.misc.Unsafe;

public class UnsafeCas {
    private int val;

    public static void main(String[] a) {
        Unsafe U = Unsafe.getUnsafe();
        long off = U.objectFieldOffset(UnsafeCas.class, "val");
        UnsafeCas t = new UnsafeCas();
        U.putInt(t, off, 5);
        System.out.println(U.getInt(t, off));                            // 5
        System.out.println(U.getAndAddInt(t, off, 10));                  // 5 (old)
        System.out.println(U.getInt(t, off));                            // 15
        System.out.println(U.compareAndSetInt(t, off, 15, 20) ? 1 : 0);  // 1
        System.out.println(U.getInt(t, off));                            // 20
        System.out.println(U.compareAndSetInt(t, off, 99, 30) ? 1 : 0);  // 0 (fails)
        System.out.println(U.getAndSetInt(t, off, 7));                   // 20 (old)
        System.out.println(U.getInt(t, off));                            // 7
    }
}
