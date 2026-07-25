#!/bin/sh
# java.io as compiled Java stubs (stdlib/java/io) over 7 fd-based native leaves
# (__fjc_io_* → jrt_io_*). Byte streams: write a byte[]+a byte, read back, EOF.
# Char streams: BufferedWriter/Reader line round-trip. IOException on open failure.
# All heap-balanced. No per-class compiler code — the general stub + __fjc_ path.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
io="$root/stdlib/out/java/io"
work="$(mktemp -d)"; trap 'rm -rf "$work" /tmp/fjc_fileio_test.bin /tmp/fjc_text.txt /tmp/fjc_nonexistent_zzz.bin' EXIT
[ -x "$fastjavac" ] || { echo "FAIL fileio (fastjavac missing)"; exit 1; }
sh "$root/stdlib/build.sh" >/dev/null 2>&1
[ -e "$io/FileInputStream.class" ] || { echo "FAIL fileio (java.io stubs not built)"; exit 1; }

check() { # name mainclass want-nums
    nm="$1"; mc="$2"; want="$3"
    if ! javac -cp "$root/stdlib/out" -d "$work" "$ex/$mc.java" 2>"$work/j"; then
        echo "FAIL $nm (javac): $(head -1 "$work/j")"; exit 1; fi
    if ! "$fastjavac" --dynamic -o "$work/$mc" "$work/$mc.class" "$io"/*.class 2>"$work/h"; then
        echo "FAIL $nm (build): $(cat "$work/h")"; exit 1; fi
    out="$(FASTLLVM_HEAPSTATS=1 "$work/$mc" 2>&1)"; code=$?
    [ "$code" = 0 ] || { echo "FAIL $nm (exit $code): $out"; exit 1; }
    got="$(echo "$out" | grep -E '^-?[0-9]+$' | tr '\n' ' ')"
    [ "$got" = "$want" ] || { echo "FAIL $nm (got '$got', want '$want'): $out"; exit 1; }
    if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
        echo "FAIL $nm (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
}

rm -f /tmp/fjc_fileio_test.bin
check fileio-bytes FileIo "6 -1 65 66 67 68 69 70 "
disk="$(od -An -tx1 /tmp/fjc_fileio_test.bin 2>/dev/null | tr -d ' \n')"
[ "$disk" = "414243444546" ] || { echo "FAIL fileio-bytes (disk '$disk', want 414243444546)"; exit 1; }

rm -f /tmp/fjc_nonexistent_zzz.bin
check fileio-exc IoExc "7 1 "         # FileNotFoundException caught as Exception

rm -f /tmp/fjc_text.txt
check fileio-text TextIo "2 "         # readLine prints hello/world (non-numeric) then 2
grep -qx hello /tmp/fjc_text.txt && grep -qx world /tmp/fjc_text.txt || { echo "FAIL fileio-text (file content)"; exit 1; }

echo "ok   fileio"
