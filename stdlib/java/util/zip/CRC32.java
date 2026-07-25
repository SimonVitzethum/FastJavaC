package java.util.zip;
// java.util.zip.CRC32 whose checksum is computed by the REAL JDK libzip native
// leaf via the runtime JNI bridge — no reimplementation of the CRC algorithm.
public class CRC32 {
    private int crc = 0;
    public void update(byte[] b) { update(b, 0, b.length); }
    public void update(byte[] b, int off, int len) {
        crc = FjcZip.__fjc_jni_crc32(crc, b, off, len);
    }
    public long getValue() { return ((long) crc) & 0xFFFFFFFFL; }
    public void reset() { crc = 0; }
}
