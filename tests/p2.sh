#!/bin/sh
# Phase 2 (runtime method redefinition) end-to-end test: a --dynamic host calls a
# virtual method, loads a native module, redefines the method by repointing its
# vtable slot to the module's implementation, and observes the changed behavior.
# No VM/JIT: redefinition is a single pointer store into a mutable vtable.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples"
fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

[ -x "$fastjavac" ] || { echo "FAIL p2 (fastjavac missing)"; exit 1; }

if ! javac -d "$work" "$ex/PatchMod.java" "$ex/RedefHost.java" 2>"$work/jerr"; then
    echo "FAIL p2 (javac): $(head -1 "$work/jerr")"; exit 1
fi
if ! "$fastjavac" --emit-module --main PatchMod -o "$work/patch.so" "$work/PatchMod.class" 2>"$work/merr"; then
    echo "FAIL p2 (module build): $(cat "$work/merr")"; exit 1
fi
if ! "$fastjavac" --dynamic -o "$work/rhost" "$work/RedefHost.class" "$work/Greeter.class" 2>"$work/herr"; then
    echo "FAIL p2 (host build): $(cat "$work/herr")"; exit 1
fi

out="$(cd "$work" && ./rhost 2>&1)"; code=$?
if [ "$code" != 0 ]; then
    echo "FAIL p2 (exit $code): $out"; exit 1
fi
# Expect the original result (1) then the redefined result (2).
if [ "$(echo "$out" | sed -n 1p)" != 1 ] || [ "$(echo "$out" | sed -n 2p)" != 2 ]; then
    echo "FAIL p2 (redefinition not observed): $out"; exit 1
fi
echo "ok   p2_redefine"
