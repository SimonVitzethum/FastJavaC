#!/bin/sh
# Fully JIT-defined polymorphic subclass (the mod/Mixin pattern): a JIT-defined class
# extends an AOT class and overrides a method; a JITted method news it and dispatches the
# override virtually. Requires JIT RC (object freed) + the native ABI (override gets the
# right receiver). Heap must balance. x86-64 only.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_mod (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitmod (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/Beast.java" "$ex/Cub.java" "$ex/ModHost.java" 2>"$work/j"; then
    echo "FAIL jitmod (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/mh" "$work/ModHost.class" "$work/Beast.class" 2>"$work/h"; then
    echo "FAIL jitmod (host build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./mh 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jitmod (exit $code): $out"; exit 1; }
echo "$out" | grep -q '^9$' || { echo "FAIL jitmod (override not dispatched): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jitmod (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   jit_mod"
