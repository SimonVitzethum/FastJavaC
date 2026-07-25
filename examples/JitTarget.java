// Tier-1 JIT target: its bytecode is read from the .class at runtime and copy-and-patch
// compiled to native code by the host (no AOT of these methods, no subprocess).
public class JitTarget {
    static int square(int x) { return x * x; }
    static int sumTo(int n) { int s = 0; for (int i = 1; i <= n; i++) s += i; return s; } // loop
}
