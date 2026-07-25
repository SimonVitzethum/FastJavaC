// Buffered character I/O over the java.io stub stack: BufferedWriter→FileWriter→
// OutputStreamWriter→FileOutputStream writes text; BufferedReader→FileReader→
// InputStreamReader→FileInputStream reads it back line-by-line (readLine). The
// whole stack is compiled Java stubs (stdlib/java/io) bottoming out in 7 fd leaves.
import java.io.*;
public class TextIo {
    public static void main(String[] a) throws Exception {
        String path = "/tmp/fjc_text.txt";
        // write two lines via BufferedWriter over FileWriter
        BufferedWriter w = new BufferedWriter(new FileWriter(path));
        w.write("hello");
        w.newLine();
        w.write("world");
        w.newLine();
        w.close();
        // read back via BufferedReader over FileReader
        BufferedReader r = new BufferedReader(new FileReader(path));
        String line;
        int n = 0;
        while ((line = r.readLine()) != null) {
            System.out.println(line);
            n++;
        }
        r.close();
        System.out.println(n);   // 2
    }
}
