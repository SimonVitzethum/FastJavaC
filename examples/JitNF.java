// JIT-defined at runtime: float arithmetic (xmm ss) and object creation (new + <init> via
// invokespecial + areturn, the RC-correct factory pattern).
public class JitNF {
    static float fsum(float x) { return x + x + 1.0f; }   // float via xmm
    static Object makeCell() { return new Cell(); }        // new + invokespecial <init> + areturn
}
