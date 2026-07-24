// M2 module delivered as bytecode: a plain jar (Main-Class: ModJar). The host loads
// it at runtime; the loader compiles it to a native module on first use (cached),
// then runs it. Its main() prints a value so the host can observe it ran natively.
public class ModJar {
    public static void main(String[] args) {
        System.out.println(99);
    }
}
