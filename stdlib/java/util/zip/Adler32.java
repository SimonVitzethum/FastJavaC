package java.util.zip;
public class Adler32 {
    private int adler = 1;   // Adler-32 seed is 1
    public void update(byte[] b) { update(b, 0, b.length); }
    public void update(byte[] b, int off, int len) {
        adler = FjcZip.__fjc_jni_ii_aii("Java_java_util_zip_Adler32_updateBytes", adler, b, off, len);
    }
    public long getValue() { return ((long) adler) & 0xFFFFFFFFL; }
    public void reset() { adler = 1; }
}
