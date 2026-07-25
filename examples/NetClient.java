// TCP client over the java.net stub stack (Socket → SocketInput/OutputStream,
// reusing the fd-based jrt_io_* leaves; only connect/listen/accept are new
// native leaves). Connects to a loopback echo server, sends "PING\n", echoes
// the reply bytes. The whole stack is compiled Java stubs (stdlib/java/net +
// stdlib/java/io) bottoming out in ~10 fd/socket leaves. Heap-balanced.
import java.net.Socket;
import java.io.InputStream;
import java.io.OutputStream;
public class NetClient {
    public static void main(String[] a) throws Exception {
        Socket s = new Socket("127.0.0.1", 54488);
        OutputStream out = s.getOutputStream();
        out.write('P'); out.write('I'); out.write('N'); out.write('G'); out.write('\n');
        InputStream in = s.getInputStream();
        int b, n = 0;
        while ((b = in.read()) != -1) { System.out.println(b); n++; if (b == 10) break; }
        s.close();
        System.out.println(n);
    }
}
