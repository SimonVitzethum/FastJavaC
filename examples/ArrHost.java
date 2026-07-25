// Tier-1 JIT arrays: a JITted method allocates an int[], fills and sums it, and the
// array is reference-counted (freed -> heap balances). All native.
public class ArrHost {
    static native int __fjc_file_size(String path);
    static native int __fjc_read_into(byte[] buf, String path);
    static native int __fjc_define_class(byte[] classBytes);
    static native long __fjc_call(String cls, String method, String desc, int arg);

    public static void main(String[] args) {
        int sz = __fjc_file_size("./ArrCalc.class");
        byte[] cls = new byte[sz];
        __fjc_read_into(cls, "./ArrCalc.class");
        __fjc_define_class(cls);
        long r = __fjc_call("ArrCalc", "sumSquares", "(I)I", 5);   // 0+1+4+9+16 = 30
        if (r != 30) throw new RuntimeException("array " + r);
        System.out.println(r);
    }
}
