package java.net;
import java.io.IOException;
public class ServerSocket {
    private int fd;
    public ServerSocket(int port) throws IOException {
        fd = FjcNet.__fjc_net_listen(port, 16);
        if (fd < 0) throw new IOException("bind failed");
    }
    public Socket accept() throws IOException {
        int c = FjcNet.__fjc_net_accept(fd);
        if (c < 0) throw new IOException("accept failed");
        return new Socket(c);
    }
    public void close() throws IOException { FjcNet.__fjc_io_close(fd); fd = -1; }
}
