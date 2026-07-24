#!/bin/sh
# Phase 5 (binary trampoline patching) end-to-end test: a --dynamic host loads a
# module, then rewrites 12 machine-code bytes at a method's patchable entry to jump
# to the module's implementation (self-modifying code), and observes the redirect.
# W^X-aware (RWX-in-place, /proc/self/mem fallback). No VM, no JIT.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples"
fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

[ -x "$fastjavac" ] || { echo "FAIL p5 (fastjavac missing)"; exit 1; }

if ! javac -d "$work" "$ex/HotPatchMod.java" "$ex/HotHost.java" 2>"$work/jerr"; then
    echo "FAIL p5 (javac): $(head -1 "$work/jerr")"; exit 1
fi
if ! "$fastjavac" --emit-module --main HotPatchMod -o "$work/hotpatch.so" "$work/HotPatchMod.class" 2>"$work/merr"; then
    echo "FAIL p5 (module build): $(cat "$work/merr")"; exit 1
fi
if ! "$fastjavac" --dynamic -o "$work/hhost" "$work/HotHost.class" "$work/Greeter3.class" 2>"$work/herr"; then
    echo "FAIL p5 (host build): $(cat "$work/herr")"; exit 1
fi

out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./hhost 2>&1)"; code=$?
if [ "$code" != 0 ]; then echo "FAIL p5 (exit $code): $out"; exit 1; fi
if [ "$(echo "$out" | sed -n 1p)" != 1 ] || [ "$(echo "$out" | sed -n 2p)" != 2 ]; then
    echo "FAIL p5 (trampoline patch not observed): $out"; exit 1
fi
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL p5 (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1
fi
echo "ok   p5_trampoline_patch"
