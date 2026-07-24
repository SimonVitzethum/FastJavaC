// Phase 0 introspection test: a program queries its own FjcClass runtime metadata
// through the reserved `__fjc_*` compiler intrinsics (backed by the jrt_ registry).
public class FjcIntro {
    static native int __fjc_field_count(String c);
    static native int __fjc_method_count(String c);
    static native int __fjc_instance_size(String c);

    public static void main(String[] args) {
        Point p = new Point(3, 4);

        int fields = __fjc_field_count("Point");   // x, y -> 2
        int methods = __fjc_method_count("Point");  // <init>, sum -> 2
        int unknown = __fjc_field_count("Nope");    // absent -> -1
        int size = __fjc_instance_size("Point");    // 2-word header + 2 ints = 24

        if (fields != 2) throw new RuntimeException("field count " + fields);
        if (methods != 2) throw new RuntimeException("method count " + methods);
        if (unknown != -1) throw new RuntimeException("unknown lookup " + unknown);
        if (size != 24) throw new RuntimeException("instance size " + size);

        System.out.println(fields);
        System.out.println(methods);
        System.out.println(size);
        System.out.println(p.sum());
    }
}

class Point {
    int x, y;
    Point(int x, int y) { this.x = x; this.y = y; }
    int sum() { return x + y; }
}
