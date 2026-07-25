// JIT field-access host: defines Accessor at runtime, then calls its methods which
// read and write the fields of an AOT Cell object — field offsets resolved from the
// FjcClass registry. All native, dispatched by name.
public class FieldHost {
    static native int __fjc_file_size(String path);
    static native int __fjc_read_into(byte[] buf, String path);
    static native int __fjc_define_class(byte[] classBytes);
    static native int __fjc_call_obj1(String cls, String method, String desc, Object arg);

    public static void main(String[] args) {
        int sz = __fjc_file_size("./Accessor.class");
        byte[] cls = new byte[sz];
        __fjc_read_into(cls, "./Accessor.class");
        __fjc_define_class(cls);

        Cell c = new Cell();
        c.v = 5;
        int got = __fjc_call_obj1("Accessor", "getV", "(LCell;)I", c);   // 5 (getfield)
        int bumped = __fjc_call_obj1("Accessor", "bump", "(LCell;)I", c); // 6 (getfield+putfield)
        if (got != 5 || bumped != 6 || c.v != 6)
            throw new RuntimeException("field " + got + "," + bumped + "," + c.v);
        System.out.println(got);
        System.out.println(bumped);
    }
}
