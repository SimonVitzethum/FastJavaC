package java.io;
public class BufferedReader extends Reader {
    private Reader in;
    public BufferedReader(Reader in) { this.in = in; }
    public int read() throws IOException { return in.read(); }
    public String readLine() throws IOException {
        int c = in.read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c != -1 && c != '\n') {
            if (c != '\r') sb.append((char) c);
            c = in.read();
        }
        return sb.toString();
    }
    public void close() throws IOException { in.close(); }
}
