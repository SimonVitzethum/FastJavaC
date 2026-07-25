// Automatic JNI native-method binding: an ordinary `native` method (no __fjc_, no
// compiler glue) auto-binds to its standard Java_<class>_<method> symbol in a
// System.load-ed lib and is called via the libffi JNI bridge. This is how
// unmodified JNI/LWJGL Java runs. The test builds libnativeadd.so alongside.
public class NativeAdd {
    static native int addNative(int a, int b);
    static native long mulNative(long a, long b);
    public static void main(String[] x) {
        System.load("./libnativeadd.so");
        System.out.println(addNative(3, 4));               // 7
        System.out.println(mulNative(100000L, 100000L));   // 10000000000
    }
}
