public class JitOpsHost {
    static native int __fjc_jit_run(String cls, String method, String desc, int arg);
    public static void main(String[] a) {
        System.out.println(__fjc_jit_run("./JitOps.class", "bitops", "(I)I", 10));
        System.out.println(__fjc_jit_run("./JitOps.class", "longops", "(I)I", 5));
        System.out.println(__fjc_jit_run("./JitOps.class", "arrconv", "(I)I", 7));
    }
}
