#!/bin/sh
# Tier-1 JIT reference counting: a JIT-defined method allocates objects (new) and returns
# a primitive; the JIT must release the locally-created objects at the return so the heap
# balances to 0 live. x86-64 only.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jit_rc (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitrc (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/Widget.java" "$ex/RcMaker.java" "$ex/RcHost.java" 2>"$work/j"; then
    echo "FAIL jitrc (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/rc" "$work/RcHost.class" "$work/Widget.class" 2>"$work/h"; then
    echo "FAIL jitrc (host build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./rc 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jitrc (exit $code): $out"; exit 1; }
echo "$out" | grep -q '^7$' || { echo "FAIL jitrc (wrong result): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jitrc (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   jit_rc"
