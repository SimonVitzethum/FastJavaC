package java.io;
public class FileWriter extends OutputStreamWriter {
    public FileWriter(String name) throws IOException { super(new FileOutputStream(name)); }
    public FileWriter(String name, boolean append) throws IOException { super(new FileOutputStream(name, append)); }
}
