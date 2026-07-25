// JIT-defined; calls AOT methods that use `this`: a constructor that sets a field
// (invokespecial) and a getter (invokevirtual). Both need the native args-in-registers ABI.
public class AbiCaller {
    static int make(int x) { Counter c = new Counter(x); return c.get(); } // new + AOT ctor(this,x) + invokevirtual get()
}
