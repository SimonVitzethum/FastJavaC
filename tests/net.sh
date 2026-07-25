#!/bin/sh
# TCP sockets via the java.net stub stack (Socket/ServerSocket over the fd-based
# jrt_io_* leaves + connect/listen/accept). Client connects to a loopback echo
# server; must echo PING (80/73/78/71/10) and count 5, heap-balanced. Needs a
# helper echo server (python3); skips cleanly if unavailable. No compiler code
# per class — compiled Java stubs + the general __fjc_ leaf convention.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
io="$root/stdlib/out/java/io"; net="$root/stdlib/out/java/net"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL net (fastjavac missing)"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ok   net (skipped: no python3 echo helper)"; exit 0; }
sh "$root/stdlib/build.sh" >/dev/null 2>&1
if ! javac -cp "$root/stdlib/out" -d "$work" "$ex/NetClient.java" 2>"$work/j"; then
    echo "FAIL net (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/nc" "$work/NetClient.class" "$io"/*.class "$net"/*.class 2>"$work/h"; then
    echo "FAIL net (build): $(cat "$work/h")"; exit 1; fi
# background loopback echo server
python3 -c '
import socket
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 54488)); srv.listen(1)
c,_ = srv.accept()
d = c.recv(64); c.sendall(d); c.close(); srv.close()
' &
spid=$!
sleep 1
out="$(FASTLLVM_HEAPSTATS=1 "$work/nc" 2>&1)"; code=$?
wait $spid 2>/dev/null
[ "$code" = 0 ] || { echo "FAIL net (exit $code): $out"; exit 1; }
got="$(echo "$out" | grep -E '^[0-9]+$' | tr '\n' ' ')"
[ "$got" = "80 73 78 71 10 5 " ] || { echo "FAIL net (got '$got', want '80 73 78 71 10 5'): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL net (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   net"
