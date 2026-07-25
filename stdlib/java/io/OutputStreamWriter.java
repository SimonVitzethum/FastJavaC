package java.io;
public class OutputStreamWriter extends Writer {
    private OutputStream out;
    public OutputStreamWriter(OutputStream out) { this.out = out; }
    public void write(int c) throws IOException { out.write(c & 0xFF); }
    public void flush() throws IOException { out.flush(); }
    public void close() throws IOException { out.close(); }
}
