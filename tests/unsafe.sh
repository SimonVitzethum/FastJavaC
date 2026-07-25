#!/bin/sh
# jdk.internal.misc.Unsafe int-family native layer: objectFieldOffset folds to the
# real struct byte offset; get/put/compareAndSet/getAndAdd/getAndSet hit the field
# atomically. This is the primitive java.util.concurrent atomics are built on.
# Output must be 5/5/15/1/20/0/20/7 and heap-balance. x86-64 (atomics) assumed.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL unsafe (fastjavac missing)"; exit 1; }
# jdk.internal.misc.Unsafe needs the export; skip cleanly on a JDK/setup without it.
if ! javac --add-exports java.base/jdk.internal.misc=ALL-UNNAMED -d "$work" "$ex/UnsafeCas.java" 2>"$work/j"; then
    echo "ok   unsafe (skipped: javac cannot export jdk.internal.misc)"; exit 0; fi
if ! "$fastjavac" --dynamic -o "$work/uc" "$work"/UnsafeCas*.class 2>"$work/h"; then
    echo "FAIL unsafe (build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./uc 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL unsafe (exit $code): $out"; exit 1; }
got="$(echo "$out" | grep -E '^[0-9]+$' | tr '\n' ' ')"
[ "$got" = "5 5 15 1 20 0 20 7 " ] || { echo "FAIL unsafe (got '$got', want '5 5 15 1 20 0 20 7'): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL unsafe (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   unsafe"
