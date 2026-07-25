// defineClass(byte[]) / in-memory JIT: JIT bytecode that exists only in memory — the
// bridge to runtime bytecode generation (ASM/Mixin/ByteBuddy emit exactly such bytes).
// No file for the method body, no subprocess: runtime bytes -> native machine code.
public class JitMemHost {
    static native int __fjc_jit_raw(byte[] bytecode, int arg);
    static native int __fjc_file_size(String path);
    static native int __fjc_read_into(byte[] buf, String path);
    static native int __fjc_define_and_run(byte[] classFile, String method, String desc, int arg);

    public static void main(String[] args) {
        // (1) Method bytecode AUTHORED AT RUNTIME (in memory):
        //     iload_0, iload_0, iadd, ireturn  ==  2 * x
        byte[] bc = { (byte) 0x1a, (byte) 0x1a, (byte) 0x60, (byte) 0xac };
        int r1 = __fjc_jit_raw(bc, 21);                                 // 42

        // (2) defineClass(byte[]): a full class file in memory, JIT one method from it.
        int sz = __fjc_file_size("./JitTarget.class");
        byte[] cls = new byte[sz];
        __fjc_read_into(cls, "./JitTarget.class");
        int r2 = __fjc_define_and_run(cls, "square", "(I)I", 6);        // 36

        if (r1 != 42 || r2 != 36) throw new RuntimeException("mem-jit " + r1 + "," + r2);
        System.out.println(r1);
        System.out.println(r2);
    }
}
