#!/bin/sh
# java.io FileInputStream/FileOutputStream over real syscalls: write a byte[] + a
# byte, read back, hit EOF. Output 6/-1/65..70, file content ABCDEF, heap 0.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work" /tmp/fjc_fileio_test.bin' EXIT
[ -x "$fastjavac" ] || { echo "FAIL fileio (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/FileIo.java" 2>"$work/j"; then
    echo "FAIL fileio (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/fio" "$work"/FileIo*.class 2>"$work/h"; then
    echo "FAIL fileio (build): $(cat "$work/h")"; exit 1; fi
rm -f /tmp/fjc_fileio_test.bin
out="$(FASTLLVM_HEAPSTATS=1 "$work/fio" 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL fileio (exit $code): $out"; exit 1; }
got="$(echo "$out" | grep -E '^-?[0-9]+$' | tr '\n' ' ')"
[ "$got" = "6 -1 65 66 67 68 69 70 " ] || { echo "FAIL fileio (got '$got'): $out"; exit 1; }
# verify the bytes actually reached disk
disk="$(od -An -tx1 /tmp/fjc_fileio_test.bin 2>/dev/null | tr -d ' \n')"
[ "$disk" = "414243444546" ] || { echo "FAIL fileio (disk content '$disk', want 414243444546)"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL fileio (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi

# Open failure throws a catchable IOException (caught → 7, then 1), heap-balanced.
rm -f /tmp/fjc_nonexistent_zzz.bin
if ! javac -d "$work" "$ex/IoExc.java" 2>"$work/j2"; then
    echo "FAIL fileio-exc (javac): $(head -1 "$work/j2")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/ioexc" "$work"/IoExc*.class 2>"$work/h2"; then
    echo "FAIL fileio-exc (build): $(cat "$work/h2")"; exit 1; fi
eout="$(FASTLLVM_HEAPSTATS=1 "$work/ioexc" 2>&1)"; ecode=$?
[ "$ecode" = 0 ] || { echo "FAIL fileio-exc (exit $ecode): $eout"; exit 1; }
egot="$(echo "$eout" | grep -E '^[0-9]+$' | tr '\n' ' ')"
[ "$egot" = "7 1 " ] || { echo "FAIL fileio-exc (got '$egot', want '7 1' — IOException not caught): $eout"; exit 1; }
if echo "$eout" | grep -q '\[heap\]' && ! echo "$eout" | grep -q '0 still live'; then
    echo "FAIL fileio-exc (heap leak): $(echo "$eout" | grep '\[heap\]')"; exit 1; fi
echo "ok   fileio"
