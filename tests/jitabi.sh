#!/bin/sh
# Tier-1 JIT <-> AOT native ABI: a JITted method calls AOT methods that use `this`
# (a constructor that sets a field via invokespecial, and a virtual getter). Native
# register marshalling must deliver the correct receiver/args; JIT RC frees the object.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_abi (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitabi (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/Counter.java" "$ex/AbiCaller.java" "$ex/AbiHost.java" 2>"$work/j"; then
    echo "FAIL jitabi (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/ah" "$work/AbiHost.class" "$work/Counter.class" 2>"$work/h"; then
    echo "FAIL jitabi (host build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./ah 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jitabi (exit $code): $out"; exit 1; }
echo "$out" | grep -q '^42$' || { echo "FAIL jitabi (wrong result): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jitabi (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   jit_abi"
