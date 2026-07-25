#!/bin/sh
# Tier-1 JIT virtual dispatch: a JIT-defined method (VCaller.callSpeak) invokes a virtual
# method; the implementation is selected at runtime from the receiver's vtable (Beast vs
# Wolf). Also verifies open-world keeps virtual methods so their vtable slots aren't null.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_virtual (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitvirtual (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/Beast.java" "$ex/Wolf.java" "$ex/VCaller.java" "$ex/VirtualHost.java" 2>"$work/j"; then
    echo "FAIL jitvirtual (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/vh" "$work/VirtualHost.class" "$work/Beast.class" "$work/Wolf.class" 2>"$work/h"; then
    echo "FAIL jitvirtual (host build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./vh 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jitvirtual (exit $code): $out"; exit 1; }
[ "$(echo "$out" | sed -n 1p)" = 1 ] && [ "$(echo "$out" | sed -n 2p)" = 2 ] || { echo "FAIL jitvirtual (no dispatch): $out"; exit 1; }
echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live' && { echo "FAIL jitvirtual (heap leak)"; exit 1; }
echo "ok   jit_virtual"
