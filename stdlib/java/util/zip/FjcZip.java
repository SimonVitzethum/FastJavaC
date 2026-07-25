package java.util.zip;
// General JNI-bridge leaf: any (int, byte[], int, int) -> int JDK native named by
// its JNI symbol. __fjc_jni_ii_aii binds to jrt_jni_ii_aii, which resolves the
// symbol across the loaded JDK libs and calls it with a minimal JNIEnv over the
// fastjavac byte[]. A new bridged checksum needs only a stub naming its symbol.
final class FjcZip {
    static native int __fjc_jni_ii_aii(String jniSymbol, int seed, byte[] b, int off, int len);
}
