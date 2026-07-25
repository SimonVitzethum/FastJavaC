// Regression: i2b/i2c/i2s narrowing conversions + dup_x1 (field-assignment as value).
public class ConvOps {
    public static void main(String[] args) {
        int x = 300;
        byte b = (byte) x;        // i2b -> 44
        int big = 70000;
        char c = (char) big;      // i2c -> 4464
        short s = (short) big;    // i2s -> 4464
        Box box = new Box();
        int r = box.set(9);       // 'return this.v = x' -> dup_x1
        if ((int) b != 44 || (int) c != 4464 || (int) s != 4464 || r != 9 || box.v != 9)
            throw new RuntimeException("conv/dup_x1 wrong");
        System.out.println((int) b);
    }
}
class Box { int v; int set(int x) { return this.v = x; } }
