// Phase 2 host: calls a virtual method, loads a module, redefines the method by
// repointing its vtable slot to the module's implementation, then calls it again
// and observes the new behavior — all as native code, no VM/JIT.
public class RedefHost {
    static native int __fjc_load_and_run(String path);
    static native int __fjc_redefine(String target, String source, String sig);

    public static void main(String[] args) {
        Greeter g = new Greeter();
        int before = g.greet();                       // original -> 1

        __fjc_load_and_run("./patch.so");             // load module (registers PatchMod)
        int rc = __fjc_redefine("Greeter", "PatchMod", "greet ()I");
        if (rc != 0) throw new RuntimeException("redefine failed " + rc);

        int after = g.greet();                        // redefined -> 2

        if (before != 1) throw new RuntimeException("before " + before);
        if (after != 2) throw new RuntimeException("after " + after);
        System.out.println(before);
        System.out.println(after);
    }
}

class Greeter {
    int greet() { return 1; }
}
