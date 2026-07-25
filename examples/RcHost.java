// Tier-1 JIT reference counting: a JITted method allocates objects and returns an int;
// the objects must be RC-freed by the JIT so the heap balances to 0 live.
public class RcHost {
    static native int __fjc_file_size(String path);
    static native int __fjc_read_into(byte[] buf, String path);
    static native int __fjc_define_class(byte[] classBytes);
    static native long __fjc_call(String cls, String method, String desc, int arg);

    public static void main(String[] args) {
        int sz = __fjc_file_size("./RcMaker.class");
        byte[] cls = new byte[sz];
        __fjc_read_into(cls, "./RcMaker.class");
        __fjc_define_class(cls);
        long r = __fjc_call("RcMaker", "build", "()I", 0);
        if (r != 7) throw new RuntimeException("build " + r);
        System.out.println(r);
    }
}
