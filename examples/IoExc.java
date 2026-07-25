// Opening a nonexistent file throws a catchable IOException (via the runtime's
// jrt_throw_ioexception → pending-exception model). The allocated stream object
// is still released on the exception path, so the heap balances.
import java.io.FileInputStream;
public class IoExc {
    public static void main(String[] a) {
        // open a non-existent file → must throw, caught as IOException
        try {
            FileInputStream fis = new FileInputStream("/tmp/fjc_nonexistent_zzz.bin");
            System.out.println(99);        // must NOT reach
            fis.close();
        } catch (Exception e) {
            System.out.println(7);         // caught
        }
        System.out.println(1);             // continue after catch
    }
}
