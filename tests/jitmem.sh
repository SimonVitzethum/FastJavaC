#!/bin/sh
# defineClass(byte[]) / in-memory JIT end-to-end test: a --dynamic host (1) authors raw
# method bytecode in a Java byte[] at runtime and JITs it, and (2) loads a class file into
# an in-memory byte[] and JITs a method from it (the defineClass(byte[]) input). Both run
# as native machine code produced in-process; the byte[]s are RC-freed (heap balances).
# x86-64 only (the JIT emits x86-64).
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples"
fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_defineclass (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitmem (fastjavac missing)"; exit 1; }

if ! javac -d "$work" "$ex/JitMemHost.java" "$ex/JitTarget.java" 2>"$work/jerr"; then
    echo "FAIL jitmem (javac): $(head -1 "$work/jerr")"; exit 1
fi
if ! "$fastjavac" --dynamic -o "$work/memhost" "$work/JitMemHost.class" 2>"$work/herr"; then
    echo "FAIL jitmem (host build): $(cat "$work/herr")"; exit 1
fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./memhost 2>&1)"; code=$?
if [ "$code" != 0 ]; then echo "FAIL jitmem (exit $code): $out"; exit 1; fi
if [ "$(echo "$out" | sed -n 1p)" != 42 ] || [ "$(echo "$out" | sed -n 2p)" != 36 ]; then
    echo "FAIL jitmem (wrong result): $out"; exit 1
fi
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jitmem (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1
fi
echo "ok   jit_defineclass"
