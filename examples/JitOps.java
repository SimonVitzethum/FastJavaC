// Tier-1 JIT target exercising newly-added opcodes: int/long shifts, bitwise
// and/or/xor, i2b narrowing, lneg, and lcmp (long comparison). Long constants
// (ldc2_w) are intentionally avoided — jrt_jit_run compiles a bare method with
// no constant-pool view, so long/double literals are a separate (documented) gap.
public class JitOps {
    static int bitops(int x) {
        int a = x << 2;          // ishl
        int b = a >> 1;          // ishr
        int c = b >>> 1;         // iushr
        int d = c & 0xFF;        // iand (int const ok)
        int e = d | 0x100;       // ior
        int f = e ^ 0x0F;        // ixor
        return (byte) f;         // i2b
    }
    static int longops(int x) {
        long a = x;              // i2l
        long s = a << 3;         // lshl
        long r = s >> 1;         // lshr
        long u = s >>> 2;        // lushr
        long n = -r;             // lneg
        long m = r & s;          // land
        long o = m | a;          // lor
        long h = o ^ u;          // lxor
        if (h > a) return (int) (h + r);   // lcmp + ladd + l2i
        return (int) (h - n);              // lsub
    }
}
