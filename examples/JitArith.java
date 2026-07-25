// Tier-1 JIT targets for the opcodes added in this change: idiv/irem/ldiv/lrem
// (checked — div-by-zero throws instead of SIGFPE), fcmpl/fcmpg/dcmpl/dcmpg (NaN
// ordering via the comparison leaves), float[]/double[] load/store (raw-bit array
// moves), instanceof (registry TypeDesc walk), and ldc/ldc_w int/float constants.
// Each method is copy-and-patch compiled at runtime and must match the reference JVM.
public class JitArith {
    static int t_idiv(int x) { return 100 / x; }                     // 16  for x=6
    static int t_irem(int x) { return 100 % x; }                     // 4   for x=6
    static int t_ldiv(int x) { long r = 600L / x; return (int) r; }  // 100
    static int t_lrem(int x) { long r = 601L % x; return (int) r; }  // 1
    static int t_fa(int x) {                                          // float[] -> 4
        float[] fa = new float[2];
        fa[0] = 1.5f; fa[1] = 2.5f;      // ldc + fastore
        return (int) (fa[0] + fa[1]);    // faload x2, fadd, f2i
    }
    static int t_da(int x) {                                          // double[] -> 6
        double[] da = new double[2];
        da[0] = 4.0; da[1] = 2.0;        // ldc2_w + dastore
        return (int) (da[0] + da[1]);    // daload x2, dadd, d2i
    }
    static int t_fcmp(int x) {                                        // fcmpl/iflt -> 1
        float a = 1.5f, b = 2.5f;
        return (a < b) ? 1 : 0;
    }
    static int t_dcmp(int x) {                                        // dcmpg/ifgt -> 1
        double a = 4.0, b = 2.0;
        return (a > b) ? 1 : 0;
    }
    static int t_instof(int x) {                                      // instanceof -> 4
        Widget w = new Widget();
        Object o = (x > 0) ? w : null;
        int a = (o instanceof Widget) ? 4 : 0;   // true  -> 4
        Object n = null;
        int b = (n instanceof Widget) ? 8 : 0;   // null  -> 0
        return a + b;
    }
    static int t_static(int x) {                                     // getstatic/putstatic -> 318 for x=6
        Stats.sum = x + 100;             // putstatic int
        int a = Stats.sum;               // getstatic int  -> 106
        Stats.big = a * 2;               // putstatic long (i2l)
        long b = Stats.big;              // getstatic long -> 212
        return a + (int) b;              // 106 + 212 = 318
    }
    // Division by zero must NOT crash (no CPU #DE): the checked leaf throws an
    // ArithmeticException (pending) and yields 0, so 42 is printed before the
    // exception surfaces at the host boundary.
    static int t_divz(int x) {
        int safe = 42;
        int bad = 100 / x;               // x == 0 -> ArithmeticException, yields 0
        return safe + bad;
    }
}
