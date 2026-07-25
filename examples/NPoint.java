// helper for NObj: a small class the native constructs via NewObject and calls.
public class NPoint {
    int x, y;
    NPoint(int x, int y) { this.x = x; this.y = y; }
    int sum() { return x + y; }
    int scale(int f) { return (x + y) * f; }
}
