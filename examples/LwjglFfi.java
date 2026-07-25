public class LwjglFfi {
    static native int  __fjc_native_load(String path);
    static native long __fjc_native_sym(String name);
    static native long __fjc_ffi_call(long addr, String argSig, int retType, long[] args);
    public static void main(String[] a) {
        // System.load equivalent: load LWJGL's self-contained native (no libjvm).
        __fjc_native_load("./liblwjgl.so");
        // call a real liblwjgl native leaf: MemoryAccessJNI.getPointerSize(env,cls)->int
        long ps = __fjc_native_sym("Java_org_lwjgl_system_MemoryAccessJNI_getPointerSize");
        System.out.println((int) __fjc_ffi_call(ps, "PP", 'I', new long[]{ 0, 0 }));   // 8
        // exercise the generic FFI dispatcher: invokeI(env,cls,funcAddr) calls funcAddr()->int.
        // point it at libc getpid -> returns the pid (>0).
        long invokeI = __fjc_native_sym("Java_org_lwjgl_system_JNI_invokeI__J");
        long getpid  = __fjc_native_sym("getpid");
        long pid = __fjc_ffi_call(invokeI, "PPJ", 'I', new long[]{ 0, 0, getpid });
        System.out.println(pid > 0 ? 1 : 0);   // 1  (LWJGL's FFI dispatcher called a fn ptr)
    }
}
