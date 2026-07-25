package java.io;
public class BufferedWriter extends Writer {
    private Writer out;
    public BufferedWriter(Writer out) { this.out = out; }
    public void write(int c) throws IOException { out.write(c); }
    public void newLine() throws IOException { out.write('\n'); }
    public void flush() throws IOException { out.flush(); }
    public void close() throws IOException { out.close(); }
}
