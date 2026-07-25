package java.net;
// Native leaves for java.net. connect/listen/accept are new; read/write/close
// reuse the fd-based jrt_io_* (a socket is just an fd), re-declared here so the
// name-based __fjc_ interception resolves them from this package too.
final class FjcNet {
    static native int __fjc_net_connect(String host, int port);
    static native int __fjc_net_listen(int port, int backlog);
    static native int __fjc_net_accept(int fd);
    static native int __fjc_io_read1(int fd);
    static native int __fjc_io_readb(int fd, byte[] b, int off, int len);
    static native void __fjc_io_write1(int fd, int x);
    static native void __fjc_io_writeb(int fd, byte[] b, int off, int len);
    static native void __fjc_io_close(int fd);
}
