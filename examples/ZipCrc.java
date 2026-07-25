// Real java.util.zip.CRC32 whose checksum is computed by the JDK's OWN libzip.so
// native leaf, reached through the runtime JNI bridge (jrt_jni_crc32 -> dlopen
// libjvm+libzip, a minimal JNIEnv over the fastjavac byte[]). No CRC reimpl.
import java.util.zip.CRC32;
public class ZipCrc {
    public static void main(String[] a) {
        byte[] data = { 104, 101, 108, 108, 111 };  // "hello"
        CRC32 c = new CRC32();
        c.update(data);
        System.out.println(c.getValue());            // expect 907060870
    }
}
