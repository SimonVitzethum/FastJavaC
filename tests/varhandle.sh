#!/bin/sh
# Signature-polymorphic java.lang.invoke.VarHandle lowered to the atomic layer —
# the mechanism modern AtomicReference is built on. A VarHandle bound via
# findVarHandle in <clinit> drives get/set/compareAndSet/getAndSet on a reference
# field; each ref op carries the RC store barrier. Output 11/1/22/0/22/11, heap 0.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL varhandle (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/VarHandleCas.java" 2>"$work/j"; then
    echo "FAIL varhandle (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/vh" "$work"/VarHandleCas*.class 2>"$work/h"; then
    echo "FAIL varhandle (build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./vh 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL varhandle (exit $code): $out"; exit 1; }
got="$(echo "$out" | grep -E '^[0-9]+$' | tr '\n' ' ')"
[ "$got" = "11 1 22 0 22 11 " ] || { echo "FAIL varhandle (got '$got', want '11 1 22 0 22 11'): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL varhandle (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   varhandle"
