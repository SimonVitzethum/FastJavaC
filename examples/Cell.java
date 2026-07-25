// AOT-compiled into the host so its FjcClass carries field offsets; a JIT-defined method
// reads/writes Cell.v by resolving that offset from the registry (getfield/putfield).
public class Cell { int v; }
