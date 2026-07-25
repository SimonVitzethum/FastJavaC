#!/bin/sh
# End-to-end LWJGL native path: fastjavac Java does System.load(liblwjgl.so) (no
# libjvm needed), calls a real liblwjgl native leaf (getPointerSize=8), and drives
# LWJGL's own generic FFI dispatcher (invokeI) to call a function pointer — all via
# the runtime's libffi bridge. Skips if no LWJGL natives jar is present.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL lwjgl (fastjavac missing)"; exit 1; }
jar="$(find /home/simon "$HOME" 2>/dev/null -iname 'lwjgl-*natives-linux.jar' | grep -iE '/lwjgl-[0-9.]+-natives-linux.jar' | head -1)"
[ -n "$jar" ] || { echo "ok   lwjgl (skipped: no LWJGL natives-linux jar)"; exit 0; }
( cd "$work" && unzip -o -q "$jar" >/dev/null 2>&1 )
so="$(find "$work" -name liblwjgl.so | head -1)"
[ -n "$so" ] || { echo "ok   lwjgl (skipped: liblwjgl.so not in jar)"; exit 0; }
cp "$so" "$work/liblwjgl.so"
if ! javac -d "$work" "$ex/LwjglFfi.java" 2>"$work/j"; then
    echo "FAIL lwjgl (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/lw" "$work"/LwjglFfi*.class 2>"$work/h"; then
    echo "FAIL lwjgl (build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && ./lw 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL lwjgl (exit $code): $out"; exit 1; }
[ "$(echo "$out" | tr '\n' ' ')" = "8 1 " ] || { echo "FAIL lwjgl (got '$out', want 8/1)"; exit 1; }
echo "ok   lwjgl (System.load liblwjgl + getPointerSize + invokeI via libffi bridge)"
