#!/bin/sh
# General libffi native-call bridge: fastjavac Java calls C functions by address +
# signature (abs(-5)=5, getpid>0=1). x86-64/hosted with libffi.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL ffi (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/FfiCall.java" 2>"$work/j"; then
    echo "FAIL ffi (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/ffi" "$work"/FfiCall*.class 2>"$work/h"; then
    echo "FAIL ffi (build — libffi missing?): $(cat "$work/h")"; exit 1; fi
out="$("$work/ffi" 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL ffi (exit $code): $out"; exit 1; }
[ "$(echo "$out" | tr '\n' ' ')" = "5 1 " ] || { echo "FAIL ffi (got '$out', want 5/1)"; exit 1; }
echo "ok   ffi"
