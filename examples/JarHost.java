// M2 host: loads a bytecode .jar at runtime via __fjc_load_jar_and_run, which
// compiles it to a native module (cached) and runs it. Called twice to exercise
// the compile-on-first-use / cache-hit-on-second-use path. No in-process JIT.
public class JarHost {
    static native int __fjc_load_jar_and_run(String path);

    public static void main(String[] args) {
        int r1 = __fjc_load_jar_and_run("./modjar.jar");
        int r2 = __fjc_load_jar_and_run("./modjar.jar");
        if (r1 != 0) throw new RuntimeException("first load " + r1);
        if (r2 != 0) throw new RuntimeException("second load " + r2);
        System.out.println("host-ok");
    }
}
