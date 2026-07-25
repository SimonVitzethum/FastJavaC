// General JNIEnv over fastjavac's object model + registry: a native reads/writes
// object fields (GetObjectClass/GetFieldID/Get-SetIntField), and manages refs +
// checks types (NewGlobalRef/DeleteGlobalRef=RC, FindClass, IsInstanceOf,
// IsSameObject). Works for ANY JNI library. The test builds libfield.so alongside.
public class FieldTest {
    int a, b;
    static native int sumFields(FieldTest o);
    static native void bump(FieldTest o);
    static native int refCheck(FieldTest o);
    public static void main(String[] x) {
        System.load("./libfield.so");
        FieldTest o = new FieldTest();
        o.a = 30; o.b = 12;
        System.out.println(sumFields(o));   // 42
        bump(o);
        System.out.println(o.a);            // 40
        System.out.println(refCheck(o));    // 11 (instanceof + same-object via a global ref)
    }
}
