#!/bin/sh
# JIT field-access test: a --dynamic host defines Accessor at runtime and calls its
# methods, which read/write fields of an AOT Cell object. The getfield/putfield byte
# offsets are resolved from Cell's FjcClass registry entry during JIT compilation.
# x86-64 only.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples"
fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_field (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitfield (fastjavac missing)"; exit 1; }

if ! javac -d "$work" "$ex/Accessor.java" "$ex/Cell.java" "$ex/FieldHost.java" 2>"$work/jerr"; then
    echo "FAIL jitfield (javac): $(head -1 "$work/jerr")"; exit 1
fi
# Cell must be AOT-compiled into the host so its FjcClass carries field offsets.
if ! "$fastjavac" --dynamic -o "$work/fh" "$work/FieldHost.class" "$work/Cell.class" 2>"$work/herr"; then
    echo "FAIL jitfield (host build): $(cat "$work/herr")"; exit 1
fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./fh 2>&1)"; code=$?
if [ "$code" != 0 ]; then echo "FAIL jitfield (exit $code): $out"; exit 1; fi
if [ "$(echo "$out" | sed -n 1p)" != 5 ] || [ "$(echo "$out" | sed -n 2p)" != 6 ]; then
    echo "FAIL jitfield (wrong result): $out"; exit 1
fi
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jitfield (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1
fi
echo "ok   jit_field"
