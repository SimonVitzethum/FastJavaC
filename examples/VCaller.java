// JIT-defined at runtime; invokevirtual on a Beast dispatches to the receiver's
// actual class (Beast or Wolf) via its runtime vtable.
public class VCaller {
    static int callSpeak(Beast b) { return b.speak(); }
}
