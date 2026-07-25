#!/bin/sh
# Tier-1 copy-and-patch JIT end-to-end test: a --dynamic host reads a .class file at
# runtime, extracts a method's bytecode (minimal in-C classfile parser), copy-and-patch
# compiles it to native x86-64, and runs it. No AOT of that method, no subprocess, no
# interpreter — the method runs as machine code produced in-process. x86-64 only.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples"
fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Skip gracefully off x86-64 (the JIT emits x86-64 machine code).
case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_tier1 (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jit (fastjavac missing)"; exit 1; }

if ! javac -d "$work" "$ex/JitTarget.java" "$ex/JitHost.java" 2>"$work/jerr"; then
    echo "FAIL jit (javac): $(head -1 "$work/jerr")"; exit 1
fi
if ! "$fastjavac" --dynamic -o "$work/jithost" "$work/JitHost.class" 2>"$work/herr"; then
    echo "FAIL jit (host build): $(cat "$work/herr")"; exit 1
fi
# Run from the class directory so "./JitTarget.class" resolves.
out="$(cd "$work" && ./jithost 2>&1)"; code=$?
if [ "$code" != 0 ]; then echo "FAIL jit (exit $code): $out"; exit 1; fi
if [ "$(echo "$out" | sed -n 1p)" != 49 ] || [ "$(echo "$out" | sed -n 2p)" != 55 ]; then
    echo "FAIL jit (wrong result): $out"; exit 1
fi
echo "ok   jit_tier1"
