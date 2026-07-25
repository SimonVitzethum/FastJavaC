// Tier-1 JIT host: reads a .class at runtime, copy-and-patch-compiles a named (I)I method
// to native machine code in-process, and runs it — the roadmap's Tier-1 JIT, in-binary.
public class JitHost {
    static native int __fjc_jit_run(String cls, String method, String desc, int arg);

    public static void main(String[] args) {
        int sq = __fjc_jit_run("./JitTarget.class", "square", "(I)I", 7);   // 49
        int sm = __fjc_jit_run("./JitTarget.class", "sumTo", "(I)I", 10);   // 55 (loop)
        if (sq != 49 || sm != 55) throw new RuntimeException("JIT wrong: " + sq + "," + sm);
        System.out.println(sq);
        System.out.println(sm);
    }
}
