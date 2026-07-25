package java.io;
public class FileOutputStream extends OutputStream {
    private int fd;
    public FileOutputStream(String name) throws IOException { this(name, false); }
    public FileOutputStream(String name, boolean append) throws IOException {
        fd = FjcIo.__fjc_io_open_write(name, append ? 1 : 0);
        if (fd < 0) throw new FileNotFoundException(name);
    }
    public void write(int b) throws IOException { FjcIo.__fjc_io_write1(fd, b); }
    public void write(byte[] b, int off, int len) throws IOException {
        FjcIo.__fjc_io_writeb(fd, b, off, len);
    }
    public void close() throws IOException { FjcIo.__fjc_io_close(fd); fd = -1; }
}
