// JIT-defined; exercises array allocation, store, load, and length (int arrays),
// with the created array RC-freed at return.
public class ArrCalc {
    static int sumSquares(int n) {
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = i * i;
        int s = 0;
        for (int i = 0; i < a.length; i++) s += a[i];
        return s;
    }
}
