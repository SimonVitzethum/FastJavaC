package java.net;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.IOException;
public class Socket {
    int fd;
    Socket(int fd) { this.fd = fd; }               // package-private: from accept()
    public Socket(String host, int port) throws IOException {
        fd = FjcNet.__fjc_net_connect(host, port);
        if (fd < 0) throw new IOException("connect failed");
    }
    public InputStream getInputStream() throws IOException { return new SocketInputStream(fd); }
    public OutputStream getOutputStream() throws IOException { return new SocketOutputStream(fd); }
    public void close() throws IOException { FjcNet.__fjc_io_close(fd); fd = -1; }
}
