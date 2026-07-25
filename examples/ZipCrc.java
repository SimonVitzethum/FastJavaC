// java.util.zip CRC32 AND Adler32 computed by the JDK's OWN libzip.so native
// leaves via the GENERAL runtime JNI bridge (jrt_jni_ii_aii resolves any
// (int,byte[],int,int)->int leaf by its JNI symbol name; minimal JNIEnv over the
// fastjavac byte[]). Adler32 is a pure Java stub — no compiler/C change to add it.
import java.util.zip.CRC32;
import java.util.zip.Adler32;
public class ZipCrc {
    public static void main(String[] a) {
        byte[] data = { 104, 101, 108, 108, 111 };  // "hello"
        CRC32 c = new CRC32(); c.update(data);
        System.out.println(c.getValue());            // 907060870
        Adler32 d = new Adler32(); d.update(data);
        System.out.println(d.getValue());            // 103547413
    }
}
