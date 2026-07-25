// JIT-defined; calls an AOT constructor and method that take/return double — the native
// ABI must route double args to xmm and read the double result from xmm0.
public class FloatCaller {
    static double calc(double a) { Vec v = new Vec(a); return v.sq(); }
}
