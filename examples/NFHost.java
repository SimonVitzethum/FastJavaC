// Host for the float + new(factory) JIT test. Instantiates Cell so its FjcClass carries a
// vtable (needed by the JITted `new Cell`), then JIT-defines JitNF and invokes its methods.
public class NFHost {
    static native int __fjc_file_size(String path);
    static native int __fjc_read_into(byte[] buf, String path);
    static native int __fjc_define_class(byte[] classBytes);
    static native float __fjc_call_f(String cls, String method, String desc, float arg);
    static native Object __fjc_call_new(String cls, String method, String desc);

    public static void main(String[] args) {
        Cell warm = new Cell();          // instantiate Cell -> its vtable is emitted
        warm.v = 1;
        int sz = __fjc_file_size("./JitNF.class");
        byte[] cls = new byte[sz];
        __fjc_read_into(cls, "./JitNF.class");
        __fjc_define_class(cls);

        float f = __fjc_call_f("JitNF", "fsum", "(F)F", 2.5f);              // 6.0
        Object o = __fjc_call_new("JitNF", "makeCell", "()Ljava/lang/Object;"); // fresh Cell
        if (f != 6.0f || o == null) throw new RuntimeException("new/float " + f + "," + o);
        System.out.println((int) f);
        System.out.println(o != null ? 1 : 0);
    }
}
