// java.io file streams over real open/read/write/close syscalls. Writes a byte[]
// plus a single byte to a file, then reads it back and hits EOF. The streams are
// runtime-backed JObjs whose drop closes the fd, so the heap balances even
// without explicit close(). (IOException is not modelled yet; paths are valid.)
import java.io.FileOutputStream;
import java.io.FileInputStream;
public class FileIo {
    public static void main(String[] a) throws Exception {
        String path = "/tmp/fjc_fileio_test.bin";
        byte[] out = new byte[]{ 65, 66, 67, 68, 69 };  // ABCDE
        FileOutputStream fos = new FileOutputStream(path);
        fos.write(out);
        fos.write(70);                                   // F
        fos.close();
        FileInputStream fis = new FileInputStream(path);
        byte[] in = new byte[6];
        int n = fis.read(in);
        System.out.println(n);                           // 6
        System.out.println(fis.read());                  // -1 (EOF)
        fis.close();
        for (int i = 0; i < n; i++) System.out.println(in[i]); // 65..70
    }
}
