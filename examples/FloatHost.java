// Tier-1 JIT float/double ABI: a JITted method passes a double to an AOT constructor and
// reads a double result from an AOT method; the created object is RC-freed at dreturn.
public class FloatHost {
    static native int __fjc_file_size(String path);
    static native int __fjc_read_into(byte[] buf, String path);
    static native int __fjc_define_class(byte[] classBytes);
    static native double __fjc_call_d(String cls, String method, String desc, double arg);

    public static void main(String[] args) {
        int sz = __fjc_file_size("./FloatCaller.class");
        byte[] cls = new byte[sz];
        __fjc_read_into(cls, "./FloatCaller.class");
        __fjc_define_class(cls);
        double r = __fjc_call_d("FloatCaller", "calc", "(D)D", 2.5);   // Vec(2.5).sq() = 6.25
        if (r != 6.25) throw new RuntimeException("float " + r);
        System.out.println(r);
    }
}
