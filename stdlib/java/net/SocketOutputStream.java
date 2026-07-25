package java.net;
import java.io.OutputStream;
import java.io.IOException;
class SocketOutputStream extends OutputStream {
    private int fd;
    SocketOutputStream(int fd) { this.fd = fd; }
    public void write(int b) throws IOException { FjcNet.__fjc_io_write1(fd, b); }
    public void write(byte[] b, int off, int len) throws IOException {
        FjcNet.__fjc_io_writeb(fd, b, off, len);
    }
}
