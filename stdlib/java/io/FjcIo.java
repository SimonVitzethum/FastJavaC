package java.io;
// Native I/O leaves (the __fjc_<name> → jrt_<name> convention). The compiler
// intercepts these by name; the fd-based jrt_io_* live in runtime.c. This is the
// ONLY native surface the whole java.io char/byte-stream stack bottoms out in.
final class FjcIo {
    static native int __fjc_io_open_read(String path);
    static native int __fjc_io_open_write(String path, int append);
    static native int __fjc_io_read1(int fd);
    static native int __fjc_io_readb(int fd, byte[] b, int off, int len);
    static native void __fjc_io_write1(int fd, int x);
    static native void __fjc_io_writeb(int fd, byte[] b, int off, int len);
    static native void __fjc_io_close(int fd);
}
