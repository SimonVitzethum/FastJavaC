// Host that copy-and-patch JITs the JitArith methods at runtime and prints their
// results. Widget is AOT-compiled into this binary (passed on the fastjavac command
// line) so the JIT resolves `new Widget` / `instanceof Widget` via the registry.
public class JitArithHost {
    static native int __fjc_jit_run(String cls, String method, String desc, int arg);
    static void t(String m, int arg) {
        System.out.println(m + "=" + __fjc_jit_run("./JitArith.class", m, "(I)I", arg));
    }
    public static void main(String[] a) {
        t("t_idiv", 6); t("t_irem", 6); t("t_ldiv", 6); t("t_lrem", 6);
        t("t_fa", 6); t("t_da", 6); t("t_fcmp", 6); t("t_dcmp", 6);
        t("t_instof", 6);
        t("t_divz", 0);   // must throw (pending), not SIGFPE
    }
}
