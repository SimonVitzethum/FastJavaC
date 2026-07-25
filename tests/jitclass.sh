#!/bin/sh
# Tier-1 JIT ClassLoader end-to-end test: a --dynamic host defines a class from an
# in-memory byte[] (JITs all methods, registers them into the FjcClass registry), then
# invokes those methods by name via the registry — like any AOT/module class. Covers
# int, 64-bit long, and object-argument methods. x86-64 only (the JIT emits x86-64).
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples"
fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_classloader (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitclass (fastjavac missing)"; exit 1; }

if ! javac -d "$work" "$ex/JitDefined.java" "$ex/JitDefHost.java" 2>"$work/jerr"; then
    echo "FAIL jitclass (javac): $(head -1 "$work/jerr")"; exit 1
fi
if ! "$fastjavac" --dynamic -o "$work/dh" "$work/JitDefHost.class" 2>"$work/herr"; then
    echo "FAIL jitclass (host build): $(cat "$work/herr")"; exit 1
fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./dh 2>&1)"; code=$?
if [ "$code" != 0 ]; then echo "FAIL jitclass (exit $code): $out"; exit 1; fi
exp="49
4000000000
0
1"
got="$(echo "$out" | grep -v '\[heap\]')"
if [ "$got" != "$exp" ]; then echo "FAIL jitclass (wrong result): $out"; exit 1; fi
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jitclass (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1
fi
echo "ok   jit_classloader"
