#!/bin/sh
# Object/System/Class core natives: System.identityHashCode, Class.isInstance,
# Class.isAssignableFrom. Output must match the reference (0/1/1/0/1/1/0/1) and
# heap-balance.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL corenatives (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/CoreNatives.java" 2>"$work/j"; then
    echo "FAIL corenatives (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/cn" "$work"/CoreNatives*.class 2>"$work/h"; then
    echo "FAIL corenatives (build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./cn 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL corenatives (exit $code): $out"; exit 1; }
got="$(echo "$out" | grep -E '^[0-9]+$' | tr '\n' ' ')"
[ "$got" = "0 1 1 0 1 1 0 1 " ] || { echo "FAIL corenatives (got '$got', want '0 1 1 0 1 1 0 1'): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL corenatives (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   corenatives"
