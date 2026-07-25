// Audit fix: JNI local-reference lifetime. A native that retrieves/creates object
// refs (GetObjectField, CallObjectMethod, NewStringUTF) must not leak them — the
// runtime opens a local-ref frame around each native call and releases the frame on
// return, keeping only the returned object. Heap must balance. General (any JNI lib).
public class ORef {
    String name = "hello";
    String make() { return "world!"; }
    static native int probe(ORef o);
    static native String makeNative();
    public static void main(String[] a) {
        System.load("./liboref.so");
        System.out.println(probe(new ORef()));   // 5 + 6 = 11 (locals freed, heap balances)
        System.out.println(makeNative());         // hi (returned string kept)
    }
}
