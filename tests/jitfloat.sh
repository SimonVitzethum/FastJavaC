#!/bin/sh
# Tier-1 JIT float/double calling convention: a JITted method passes a double arg to an
# AOT constructor (xmm register class) and reads a double result from an AOT method (xmm0);
# the object is RC-freed at dreturn. x86-64 only.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_float_abi (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitfloat (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/Vec.java" "$ex/FloatCaller.java" "$ex/FloatHost.java" 2>"$work/j"; then
    echo "FAIL jitfloat (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/fh" "$work/FloatHost.class" "$work/Vec.class" 2>"$work/h"; then
    echo "FAIL jitfloat (host build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./fh 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jitfloat (exit $code): $out"; exit 1; }
echo "$out" | grep -q '^6.25$' || { echo "FAIL jitfloat (wrong result): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jitfloat (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   jit_float_abi"
