package java.util.zip;
// Native leaf: CRC32 over a byte[] region, computed by the JDK's OWN libzip.so
// reached through the runtime JNI bridge (jrt_jni_crc32). The __fjc_ name binds
// to jrt_jni_crc32; the bridge dlopens libjvm+libzip (paths from $JAVA_HOME).
final class FjcZip {
    static native int __fjc_jni_crc32(int crc, byte[] b, int off, int len);
}
