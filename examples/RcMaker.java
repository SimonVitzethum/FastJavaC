// JIT-defined: creates objects in a JITted method and returns a primitive. With JIT-side
// reference counting, the locally-created objects are released at the return -> 0 live.
public class RcMaker {
    static int build() {
        Widget a = new Widget();
        Widget b = new Widget();
        return a.v + b.v + 7;   // 7 (fields default 0)
    }
}
