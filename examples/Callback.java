// Native → Java method callbacks via the JNIEnv: GetMethodID/GetStaticMethodID +
// Call<T>Method, dispatched virtually through the object's vtable (so an override
// is picked) or directly for static/exact methods, over fastjavac's native ABI via
// libffi. General — any JNI library that calls back into Java. Builds libcb.so.
public class Callback extends Base {
    int doubleIt(int x) { return x * 2; }
    int greet() { return 7; }               // overrides Base.greet() — virtual dispatch
    static int triple(int x) { return x * 3; }
    static native int run(Callback o);
    public static void main(String[] a) {
        System.load("./libcb.so");
        System.out.println(run(new Callback()));   // 42 + 7 + 9 = 58
    }
}
