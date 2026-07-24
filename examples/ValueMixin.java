// Phase 3 mixin: overwrites value() and reads a shadowed field `base` that resolves
// against the TARGET's layout after weaving (the mixin @Shadow contract). Woven with
// --weave ValueMixin:WeaveBase, value() becomes base + 15 on WeaveBase instances.
public class ValueMixin {
    int base; // @Shadow of WeaveBase.base — rewritten to the target class on weave
    int value() { return base + 15; }
}
