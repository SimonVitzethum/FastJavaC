#!/bin/sh
# Phase 3 (compile-time mixin weaving) test: a mixin overwrites a target method
# (reading a shadowed field that resolves against the target's layout). The woven
# class is compiled to a normal native binary; no VM, no runtime bytecode work.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples"
fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

[ -x "$fastjavac" ] || { echo "FAIL p3 (fastjavac missing)"; exit 1; }

if ! javac -d "$work" "$ex/WeaveBase.java" "$ex/ValueMixin.java" 2>"$work/jerr"; then
    echo "FAIL p3 (javac): $(head -1 "$work/jerr")"; exit 1
fi
if ! "$fastjavac" --weave ValueMixin:WeaveBase -o "$work/app" \
        "$work/WeaveBase.class" "$work/ValueMixin.class" 2>"$work/berr"; then
    echo "FAIL p3 (weave build): $(cat "$work/berr")"; exit 1
fi
out="$(FASTLLVM_HEAPSTATS=1 "$work/app" 2>&1)"; code=$?
if [ "$code" != 0 ]; then echo "FAIL p3 (exit $code): $out"; exit 1; fi
if ! echo "$out" | grep -q '^20$'; then echo "FAIL p3 (mixin not woven): $out"; exit 1; fi
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL p3 (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1
fi
echo "ok   p3_mixin_weave"
