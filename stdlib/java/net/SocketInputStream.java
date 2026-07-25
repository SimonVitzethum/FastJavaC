package java.net;
import java.io.InputStream;
import java.io.IOException;
class SocketInputStream extends InputStream {
    private int fd;
    SocketInputStream(int fd) { this.fd = fd; }
    public int read() throws IOException { return FjcNet.__fjc_io_read1(fd); }
    public int read(byte[] b, int off, int len) throws IOException {
        return FjcNet.__fjc_io_readb(fd, b, off, len);
    }
}
