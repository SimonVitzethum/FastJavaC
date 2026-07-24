// Phase 5 host: calls a method, loads a module, then trampoline-patches the method's
// native entry (rewrites 12 machine-code bytes to jmp to the module's impl) and
// observes the redirect. W^X-compliant patch; no VM, no JIT.
public class HotHost {
    static native int __fjc_load_and_run(String path);
    static native int __fjc_hotpatch(String target, String source, String sig);

    public static void main(String[] args) {
        Greeter3 g = new Greeter3();
        int before = g.greet();                       // 1

        __fjc_load_and_run("./hotpatch.so");          // load module (registers HotPatchMod)
        int rc = __fjc_hotpatch("Greeter3", "HotPatchMod", "greet ()I");
        if (rc != 0) throw new RuntimeException("hotpatch failed " + rc);

        int after = g.greet();                        // 2 (redirected entry)

        if (before != 1) throw new RuntimeException("before " + before);
        if (after != 2) throw new RuntimeException("after " + after);
        System.out.println(before);
        System.out.println(after);
    }
}

class Greeter3 {
    int greet() { return 1; }
}
