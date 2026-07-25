// Tier-1 JIT <-> AOT ABI: a JITted method calls AOT methods (constructor + virtual getter)
// that read/write `this`; native-register argument marshalling delivers the correct
// receiver/args. Combined with JIT RC, the object is freed -> heap balances.
public class AbiHost {
    static native int __fjc_file_size(String path);
    static native int __fjc_read_into(byte[] buf, String path);
    static native int __fjc_define_class(byte[] classBytes);
    static native long __fjc_call(String cls, String method, String desc, int arg);

    public static void main(String[] args) {
        int sz = __fjc_file_size("./AbiCaller.class");
        byte[] cls = new byte[sz];
        __fjc_read_into(cls, "./AbiCaller.class");
        __fjc_define_class(cls);
        long r = __fjc_call("AbiCaller", "make", "(I)I", 42);   // ctor sets n=42, get() returns it
        if (r != 42) throw new RuntimeException("abi " + r);
        System.out.println(r);
    }
}
