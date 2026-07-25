#!/bin/sh
# JIT float + object-creation test: a --dynamic host JIT-defines JitNF and calls fsum
# (float arithmetic via xmm) and makeCell (new Cell + invokespecial <init> + areturn, the
# RC-correct factory pattern). Cell is AOT-instantiated in the host so its vtable exists.
# The factory-created object is RC-balanced (0 live). x86-64 only.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples"
fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_new_float (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitnew (fastjavac missing)"; exit 1; }

if ! javac -d "$work" "$ex/JitNF.java" "$ex/Cell.java" "$ex/NFHost.java" 2>"$work/jerr"; then
    echo "FAIL jitnew (javac): $(head -1 "$work/jerr")"; exit 1
fi
if ! "$fastjavac" --dynamic -o "$work/nfh" "$work/NFHost.class" "$work/Cell.class" 2>"$work/herr"; then
    echo "FAIL jitnew (host build): $(cat "$work/herr")"; exit 1
fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./nfh 2>&1)"; code=$?
if [ "$code" != 0 ]; then echo "FAIL jitnew (exit $code): $out"; exit 1; fi
if [ "$(echo "$out" | sed -n 1p)" != 6 ] || [ "$(echo "$out" | sed -n 2p)" != 1 ]; then
    echo "FAIL jitnew (wrong result): $out"; exit 1
fi
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jitnew (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1
fi
echo "ok   jit_new_float"
