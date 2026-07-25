package java.io;
// Abstract byte input. Only read() is native-backed by subclasses; the array
// reads default to a read()-loop (FileInputStream overrides for a real syscall).
public abstract class InputStream {
    public abstract int read() throws IOException;
    public int read(byte[] b) throws IOException { return read(b, 0, b.length); }
    public int read(byte[] b, int off, int len) throws IOException {
        if (len == 0) return 0;
        int c = read();
        if (c == -1) return -1;
        b[off] = (byte) c;
        int i = 1;
        while (i < len) {
            c = read();
            if (c == -1) break;
            b[off + i] = (byte) c;
            i++;
        }
        return i;
    }
    public void close() throws IOException {}
}
