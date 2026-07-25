// Tier-1 JIT virtual dispatch: a JIT-defined method calls a virtual method whose
// implementation is chosen at runtime from the receiver's vtable. All native.
public class VirtualHost {
    static native int __fjc_file_size(String path);
    static native int __fjc_read_into(byte[] buf, String path);
    static native int __fjc_define_class(byte[] classBytes);
    static native int __fjc_call_obj1(String cls, String method, String desc, Object arg);

    public static void main(String[] args) {
        int sz = __fjc_file_size("./VCaller.class");
        byte[] cls = new byte[sz];
        __fjc_read_into(cls, "./VCaller.class");
        __fjc_define_class(cls);

        int base = __fjc_call_obj1("VCaller", "callSpeak", "(LBeast;)I", new Beast()); // 1
        int over = __fjc_call_obj1("VCaller", "callSpeak", "(LBeast;)I", new Wolf());  // 2
        if (base != 1 || over != 2) throw new RuntimeException("virtual " + base + "," + over);
        System.out.println(base);
        System.out.println(over);
    }
}
