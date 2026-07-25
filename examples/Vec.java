// AOT class with a double-arg constructor and a double-returning method; exercises the
// float/double register classes (xmm) when called from JITted code.
public class Vec { double x; Vec(double v) { this.x = v; } double sq() { return x * x; } }
