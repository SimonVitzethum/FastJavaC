package java.io;
public class InputStreamReader extends Reader {
    private InputStream in;
    public InputStreamReader(InputStream in) { this.in = in; }
    public int read() throws IOException { return in.read(); }
    public void close() throws IOException { in.close(); }
}
