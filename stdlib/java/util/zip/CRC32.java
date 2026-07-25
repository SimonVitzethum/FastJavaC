package java.util.zip;
public class CRC32 {
    private int crc = 0;
    public void update(byte[] b) { update(b, 0, b.length); }
    public void update(byte[] b, int off, int len) {
        crc = FjcZip.__fjc_jni_ii_aii("Java_java_util_zip_CRC32_updateBytes0", crc, b, off, len);
    }
    public long getValue() { return ((long) crc) & 0xFFFFFFFFL; }
    public void reset() { crc = 0; }
}
