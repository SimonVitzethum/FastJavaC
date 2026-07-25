// General JNI field access: a native method reads/writes this object's fields via
// GetObjectClass + GetFieldID (resolved through fastjavac's FjcClass registry) and
// Get/SetIntField (byte offset into the object). Works for ANY JNI library that
// touches object fields — not lib-specific. The test builds libfield.so alongside.
public class FieldTest {
    int a, b;
    static native int sumFields(FieldTest o);
    static native void bump(FieldTest o);
    public static void main(String[] x) {
        System.load("./libfield.so");
        FieldTest o = new FieldTest();
        o.a = 30; o.b = 12;
        System.out.println(sumFields(o));   // 42
        bump(o);
        System.out.println(o.a);            // 40
    }
}
