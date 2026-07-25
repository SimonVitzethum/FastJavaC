// AOT-compiled by the host so its @sf.Stats.* static-field globals exist and the class
// is registered — the JIT resolves getstatic/putstatic against them. No initializers, so
// the values are exactly what the JITted code writes (independent of <clinit>).
public class Stats {
    static int sum;
    static long big;
}
