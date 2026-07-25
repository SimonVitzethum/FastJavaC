// Fully JIT-defined polymorphic subclass end-to-end: define Cub (extends AOT Beast) at
// runtime; a JITted method news a Cub (inherited vtable) and dispatches its overridden
// method virtually. Needs both JIT RC (the Cub is freed) and the native ABI (the override
// is called with the correct receiver). All native, heap-balanced.
public class ModHost {
    static native int __fjc_file_size(String path);
    static native int __fjc_read_into(byte[] buf, String path);
    static native int __fjc_define_class(byte[] classBytes);
    static native long __fjc_call(String cls, String method, String desc, int arg);

    public static void main(String[] args) {
        int sz = __fjc_file_size("./Cub.class");
        byte[] cls = new byte[sz];
        __fjc_read_into(cls, "./Cub.class");
        __fjc_define_class(cls);
        long r = __fjc_call("Cub", "check", "()I", 0);   // new Cub().speak() -> 9 (override dispatched)
        if (r != 9) throw new RuntimeException("mod " + r);
        System.out.println(r);
    }
}
