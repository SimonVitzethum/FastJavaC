#!/bin/sh
# Tier-1 JIT arrays: a JITted method allocates an int[], stores/loads elements and reads
# .length in loops, and the array is RC-freed so the heap balances. x86-64 only.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_arrays (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitarr (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/ArrCalc.java" "$ex/ArrHost.java" 2>"$work/j"; then
    echo "FAIL jitarr (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/ah" "$work/ArrHost.class" 2>"$work/h"; then
    echo "FAIL jitarr (host build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./ah 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jitarr (exit $code): $out"; exit 1; }
echo "$out" | grep -q '^30$' || { echo "FAIL jitarr (wrong result): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jitarr (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   jit_arrays"
