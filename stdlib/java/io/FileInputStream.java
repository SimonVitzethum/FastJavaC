package java.io;
public class FileInputStream extends InputStream {
    private int fd;
    public FileInputStream(String name) throws IOException {
        fd = FjcIo.__fjc_io_open_read(name);
        if (fd < 0) throw new FileNotFoundException(name);
    }
    public int read() throws IOException { return FjcIo.__fjc_io_read1(fd); }
    public int read(byte[] b, int off, int len) throws IOException {
        return FjcIo.__fjc_io_readb(fd, b, off, len);
    }
    public void close() throws IOException { FjcIo.__fjc_io_close(fd); fd = -1; }
}
