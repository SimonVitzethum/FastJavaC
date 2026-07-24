// Phase 2 module: provides a replacement implementation of greet() that the host
// installs over its own Greeter.greet() at runtime via jrt_redefine (pointer swap).
public class PatchMod {
    public static int fjcMain() { return 0; } // required module entry (registers the class)
    int greet() { return 2; }                 // the override (field-agnostic — see Phase 3 for weaving)
}
