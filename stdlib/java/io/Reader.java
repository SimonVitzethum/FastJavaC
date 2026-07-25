package java.io;
public abstract class Reader {
    public abstract int read() throws IOException;
    public int read(char[] c, int off, int len) throws IOException {
        if (len == 0) return 0;
        int ch = read();
        if (ch == -1) return -1;
        c[off] = (char) ch;
        int i = 1;
        while (i < len) {
            ch = read();
            if (ch == -1) break;
            c[off + i] = (char) ch;
            i++;
        }
        return i;
    }
    public void close() throws IOException {}
}
