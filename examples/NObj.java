// General JNIEnv: NewObject (native constructs a Java object — alloc + <init> via
// the native ABI) and Call<T>Method{,A} (varargs + jvalue[] arg sources). The
// created object's ref is frame-managed (freed at native return unless returned).
public class NObj {
    static native int build();
    public static void main(String[] a) {
        System.load("./libno.so");
        System.out.println(build());   // NewObject(NPoint,3,4).sum()=7 + scale[10]=70 = 77
    }
}
