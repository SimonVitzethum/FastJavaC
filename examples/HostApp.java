// M1 host: a --dynamic binary that loads a native module (.so) at runtime through
// the reserved __fjc_load_and_run intrinsic and checks its result. The module runs
// as ordinary native code on the CPU — no VM, no JIT.
public class HostApp {
    static native int __fjc_load_and_run(String path);

    public static void main(String[] args) {
        int r = __fjc_load_and_run("./mod.so");
        if (r != 42) throw new RuntimeException("module returned " + r);
        System.out.println(r);
    }
}
