// Loaded and JIT-compiled at runtime by the host (not compiled into it). Exercises the
// broadened stencil set: int (square), long/64-bit (dbl), and reference ops (isNull).
public class JitDefined {
    static int square(int x) { return x * x; }
    static long dbl(long x) { return x + x; }               // 64-bit arithmetic
    static int isNull(Object o) { return o == null ? 1 : 0; } // object argument
}
