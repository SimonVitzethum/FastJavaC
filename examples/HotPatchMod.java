// Phase 5 module: provides the replacement greet() that the host trampoline-patches
// over its own Greeter3.greet() native entry (self-modifying machine code).
public class HotPatchMod {
    public static int fjcMain() { return 0; } // module entry (registers the class)
    int greet() { return 2; }
}
