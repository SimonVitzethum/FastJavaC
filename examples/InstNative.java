public class InstNative {
    native int getVal();          // instance native: Java_InstNative_getVal(env, this)
    native int addTo(int x);      // Java_InstNative_addTo(env, this, x)
    public static void main(String[] a) {
        System.load("./libinst.so");
        InstNative o = new InstNative();
        System.out.println(o.getVal());     // 99
        System.out.println(o.addTo(41));    // 42
        // bit intrinsics
        System.out.println(Double.doubleToRawLongBits(2.0) == 0x4000000000000000L ? 1 : 0); // 1
        System.out.println((int) Double.longBitsToDouble(0x4010000000000000L));              // 4
    }
}
