// General native-call bridge (libffi): fastjavac Java calls arbitrary C functions
// by address + signature. __fjc_native_sym resolves a symbol to its address;
// __fjc_ffi_call(addr, argSig, retType, long[] args) marshals via libffi. This is
// the FFI a JNI/LWJGL-style layer needs — it can call any GL/GLFW/... function ptr.
public class FfiCall {
    static native long __fjc_native_sym(String name);
    static native long __fjc_ffi_call(long addr, String argSig, int retType, long[] args);
    public static void main(String[] a) {
        long absA = __fjc_native_sym("abs");
        System.out.println((int) __fjc_ffi_call(absA, "I", 'I', new long[]{ -5 }));   // 5
        long pidA = __fjc_native_sym("getpid");
        System.out.println(__fjc_ffi_call(pidA, "", 'I', new long[0]) > 0 ? 1 : 0);   // 1
    }
}
