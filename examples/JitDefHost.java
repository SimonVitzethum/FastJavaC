// Tier-1 JIT ClassLoader host: defines a class from an in-memory byte[] (JITs all its
// methods and registers them into the FjcClass registry), then invokes those methods
// BY NAME through the registry — exactly as AOT/module classes are dispatched. Covers
// long/64-bit results and object arguments. All native, no interpreter.
public class JitDefHost {
    static native int __fjc_file_size(String path);
    static native int __fjc_read_into(byte[] buf, String path);
    static native int __fjc_define_class(byte[] classBytes);
    static native long __fjc_call(String cls, String method, String desc, int arg);
    static native int __fjc_call_obj1(String cls, String method, String desc, Object arg);
    static native Object __fjc_call_ref(String cls, String method, String desc, Object arg);

    public static void main(String[] args) {
        int sz = __fjc_file_size("./JitDefined.class");
        byte[] cls = new byte[sz];
        __fjc_read_into(cls, "./JitDefined.class");
        int n = __fjc_define_class(cls);                                        // register JITted class

        long sq = __fjc_call("JitDefined", "square", "(I)I", 7);                // 49
        long db = __fjc_call("JitDefined", "dbl", "(J)J", 2000000000);          // 4000000000 (64-bit)
        int notNull = __fjc_call_obj1("JitDefined", "isNull", "(Ljava/lang/Object;)I", "x"); // 0
        int isN = __fjc_call_obj1("JitDefined", "isNull", "(Ljava/lang/Object;)I", null);    // 1

        int[] token = new int[2];                                              // heap object
        Object back = __fjc_call_ref("JitDefined", "id", "(Ljava/lang/Object;)Ljava/lang/Object;", token);
        if (back != token) throw new RuntimeException("id identity");           // object return, RC-balanced

        if (n < 4 || sq != 49 || db != 4000000000L || notNull != 0 || isN != 1)
            throw new RuntimeException("jit-classloader " + n + "," + sq + "," + db + "," + notNull + "," + isN);
        System.out.println(sq);
        System.out.println(db);
        System.out.println(notNull);
        System.out.println(isN);
    }
}
