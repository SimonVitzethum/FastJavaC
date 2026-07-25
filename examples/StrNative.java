public class StrNative {
    static native int strlenNative(String s);
    static native String echoUpper(String s);
    public static void main(String[] a) {
        System.load("./libstrn.so");
        System.out.println(strlenNative("hello world"));   // 11
        System.out.println(echoUpper("abc").length());     // 3
        System.out.println(echoUpper("abc").charAt(0));    // 65 = 'A'
    }
}
