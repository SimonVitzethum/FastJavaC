// JIT-defined at runtime; reads/writes fields of the AOT class Cell. getfield/putfield
// offsets are resolved from Cell's FjcClass registry entry during JIT compilation.
public class Accessor {
    static int getV(Cell c) { return c.v; }
    static int bump(Cell c) { c.v = c.v + 1; return c.v; } // getfield + putfield + getfield
}
