package java.io;
public class FileReader extends InputStreamReader {
    public FileReader(String name) throws IOException { super(new FileInputStream(name)); }
}
