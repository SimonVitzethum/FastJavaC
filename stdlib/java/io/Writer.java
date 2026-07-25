package java.io;
public abstract class Writer {
    public abstract void write(int c) throws IOException;
    public void write(String s) throws IOException {
        int i = 0;
        while (i < s.length()) { write(s.charAt(i)); i++; }
    }
    public void write(char[] c, int off, int len) throws IOException {
        int i = 0;
        while (i < len) { write(c[off + i]); i++; }
    }
    public void flush() throws IOException {}
    public void close() throws IOException {}
}
