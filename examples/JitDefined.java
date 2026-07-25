// Loaded and JIT-compiled at runtime by the host (not compiled into it). Exercises the
// broadened stencil set: int (square), long/64-bit (dbl), and reference ops (isNull).
public class JitDefined {
    static int square(int x) { return x * x; }
    static long dbl(long x) { return x + x; }               // 64-bit arithmetic
    static int isNull(Object o) { return o == null ? 1 : 0; } // object argument
    static Object id(Object o) { return o; }                  // object return (RC +1)
    static double dsum(double x) { return x + x + 1.0; }       // double via xmm
    static double twiceTrunc(double x) { return (double) ((int) x * 2); } // d2i + i2d
    static int tryThrow(Object e) {                            // athrow + handler dispatch
        try { throw (RuntimeException) e; }
        catch (RuntimeException x) { return 42; }
    }
}
