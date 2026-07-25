// Tier-1 JIT target: int/long shifts, bitwise, i2b, lneg, lcmp, typed array
// load/store, widening + long<->float/double conversions, AND ldc2_w (long/double
// constants via the constant pool now threaded through jrt_jit_run).
public class JitOps {
    static int bitops(int x) {
        int a = x << 2;   int b = a >> 1;   int c = b >>> 1;
        int d = c & 0xFF; int e = d | 0x100; int f = e ^ 0x0F;
        return (byte) f;
    }
    static int longops(int x) {
        long a = x; long s = a << 3; long r = s >> 1; long u = s >>> 2;
        long n = -r; long m = r & s; long o = m | a; long h = o ^ u;
        if (h > a) return (int) (h + r);
        return (int) (h - n);
    }
    static int arrconv(int x) {
        long[] la = new long[3];
        la[0] = x * 1000000000L;    // ldc2_w (long constant) + lmul + i2l
        byte[] ba = new byte[4];
        ba[0] = (byte) x;
        double d = 2.5;             // ldc2_w (double constant)
        long dl = (long) (d + d);   // d2l  -> 5
        long ls = la[0];            // laload
        int bs = ba[0];             // baload
        long big = ls + 7000000000L; // ldc2_w + ladd
        return (int) (big - ls) + bs + (int) dl;  // -> 7000000000 doesn't fit int; use small
    }
}
