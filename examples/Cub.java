// JIT-defined polymorphic subclass of the AOT class Beast (the mod/Mixin pattern):
// overrides speak(); check() news a Cub and dispatches speak() virtually -> 9.
public class Cub extends Beast {
    int speak() { return 9; }                                   // override installed in the vtable
    static int check() { Beast b = new Cub(); return b.speak(); } // new + invokevirtual -> override
}
