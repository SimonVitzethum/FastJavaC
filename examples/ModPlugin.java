// M1 native module: compiled with `fastjavac --emit-module` into a .so that a
// --dynamic host loads at runtime and runs via its `static int fjcMain()` entry.
// Allocates and releases an object through the host's shared runtime (RC), so the
// host heap still balances to 0 live after the module runs.
public class ModPlugin {
    // Static field so the object escapes fjcMain -> heap allocation (not stack),
    // exercising the host's shared allocator + reference counting across the
    // module boundary. Cleared before returning so RC frees it (0 live).
    static Widget held;

    public static int fjcMain() {
        held = new Widget(20, 22);
        int r = held.total();
        held = null; // drop the last reference -> RC releases the object
        return r;
    }
}

class Widget {
    int a, b;
    Widget(int a, int b) { this.a = a; this.b = b; }
    int total() { return a + b; }
}
