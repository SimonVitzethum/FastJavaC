#!/bin/sh
# M1 (native module ABI) end-to-end test: compile a module to a .so, compile a
# --dynamic host, have the host dlopen the module and run it, and assert both the
# result (42) and a balanced heap (0 live) across the module boundary. No VM/JIT:
# the module is native machine code, loaded and linked at runtime.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples"
fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

[ -x "$fastjavac" ] || { echo "FAIL m1 (fastjavac missing — run 'cargo build')"; exit 1; }

if ! javac -d "$work" "$ex/ModPlugin.java" "$ex/HostApp.java" 2>"$work/jerr"; then
    echo "FAIL m1 (javac): $(head -1 "$work/jerr")"; exit 1
fi

# Module -> native .so (no runtime.c; jrt_* resolve against the host at load).
if ! "$fastjavac" --emit-module --main ModPlugin -o "$work/mod.so" \
        "$work/ModPlugin.class" "$work/Widget.class" 2>"$work/merr"; then
    echo "FAIL m1 (module build): $(cat "$work/merr")"; exit 1
fi

# Host -> --dynamic binary (exports jrt_*, links libdl, collector on).
if ! "$fastjavac" --dynamic -o "$work/host" "$work/HostApp.class" 2>"$work/herr"; then
    echo "FAIL m1 (host build): $(cat "$work/herr")"; exit 1
fi

# Run from the module directory so the host's "./mod.so" resolves.
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./host 2>&1)"; code=$?
if [ "$code" != 0 ]; then
    echo "FAIL m1 (exit $code): $out"; exit 1
fi
if ! echo "$out" | grep -q '^42$'; then
    echo "FAIL m1 (wrong result): $out"; exit 1
fi
# The module must have heap-allocated through the host (so the report appears) and
# balanced to 0 live across the boundary — require both, so the check isn't vacuous.
if ! echo "$out" | grep -q '\[heap\]'; then
    echo "FAIL m1 (no heap activity — module allocation was elided, test vacuous): $out"; exit 1
fi
if ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL m1 (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1
fi
echo "ok   m1_module_load"
