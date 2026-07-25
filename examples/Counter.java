// AOT class whose get() uses this (reads a field) and ctor initializes a field —
// exercises the native (this-in-RDI) ABI when called from JITted code.
public class Counter { int n; Counter(int x) { this.n = x; } int get() { return n; } }
