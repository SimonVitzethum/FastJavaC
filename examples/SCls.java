// A static `native` method now receives its real declaring class as the jclass arg
// (not NULL), so natives that use it — GetStaticMethodID/GetStaticFieldID/FindClass
// relative to their class — work. General. The test builds libscls.so alongside.
public class SCls {
    static int helper(int x) { return x * 2; }
    static native int dispatch(int x);
    public static void main(String[] a) {
        System.load("./libscls.so");
        System.out.println(dispatch(21));   // helper(21)=42, +100 = 142 (jclass used)
    }
}
