#!/bin/sh
# Reproduce the LWJGL feasibility probe: liblwjgl.so loads with no libjvm and its
# invoke dispatcher calls a function pointer. Skips if no LWJGL natives jar is found.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
jar="$(find /home/simon "$HOME" 2>/dev/null -iname 'lwjgl-*natives-linux*.jar' 2>/dev/null | grep -iE '/lwjgl-[0-9.]+-natives-linux' | head -1)"
[ -z "$jar" ] && jar="$(find /home/simon "$HOME" 2>/dev/null -iname 'lwjgl-*natives-linux.jar' | head -1)"
[ -n "$jar" ] || { echo "ok   lwjgl_probe (skipped: no LWJGL natives-linux jar found)"; exit 0; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
( cd "$work" && unzip -o -q "$jar" >/dev/null 2>&1 )
so="$(find "$work" -name 'liblwjgl.so' | head -1)"
[ -n "$so" ] || { echo "ok   lwjgl_probe (skipped: liblwjgl.so not in $jar)"; exit 0; }
cc "$here/lwjgl_probe.c" -ldl -o "$work/lp" || { echo "FAIL lwjgl_probe (build)"; exit 1; }
out="$("$work/lp" "$so" 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL lwjgl_probe: $out"; exit 1; }
echo "ok   lwjgl_probe (liblwjgl.so self-contained: getPointerSize=8, invokeI calls fn ptr)"
