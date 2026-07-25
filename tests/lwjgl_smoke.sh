#!/bin/sh
# Real-LWJGL smoke test: the SHIPPED, unmodified org.lwjgl.system.MemoryAccessJNI
# (from lwjgl-<v>.jar) compiled closed-world with minimal Library/Checks stubs
# (fastjavac's System.load replaces LWJGL's loader). Its <clinit> caches the native
# malloc/… addresses via auto-bound liblwjgl calls, then getPointerSize() -> 8 runs
# through the whole stack: real org.lwjgl class -> auto-bind -> libffi -> liblwjgl.so.
# Skips if no LWJGL jars are present.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL lwjgl_smoke (fastjavac missing)"; exit 1; }
core="$(find /home/simon "$HOME" 2>/dev/null -iname 'lwjgl-[0-9.]*.jar' | grep -iE '/lwjgl-[0-9.]+\.jar$' | head -1)"
nat="$(find /home/simon "$HOME" 2>/dev/null -iname 'lwjgl-*natives-linux.jar' | grep -iE '/lwjgl-[0-9.]+-natives-linux.jar' | head -1)"
[ -n "$core" ] && [ -n "$nat" ] || { echo "ok   lwjgl_smoke (skipped: no LWJGL jars)"; exit 0; }
command -v javac >/dev/null 2>&1 || { echo "ok   lwjgl_smoke (skipped: no javac)"; exit 0; }
mkdir -p "$work/cp" "$work/stub/org/lwjgl/system" "$work/out/org/lwjgl/system"
( cd "$work/cp" && unzip -o -q "$core" 'org/lwjgl/system/MemoryAccessJNI.class' 2>/dev/null )
( cd "$work/out" && unzip -o -q "$nat" 2>/dev/null ) ; so="$(find "$work/out" -name liblwjgl.so | head -1)"
[ -f "$work/cp/org/lwjgl/system/MemoryAccessJNI.class" ] && [ -n "$so" ] || { echo "ok   lwjgl_smoke (skipped: class/lib not found)"; exit 0; }
cp "$so" "$work/out/liblwjgl.so"
cat > "$work/stub/org/lwjgl/system/Library.java" <<'J'
package org.lwjgl.system;
public final class Library { public static void initialize() {} }
J
cat > "$work/stub/org/lwjgl/system/Checks.java" <<'J'
package org.lwjgl.system;
// Stub of the LWJGL argument-checker. check(long) is referenced by MemoryAccessJNI's
// accessor bodies; provided here so the closed world is complete (the FjcClass registry
// now retains reachable methods for dynamic getstatic/putstatic, so getByte & friends
// are no longer pruned and their call to check must resolve).
public final class Checks {
    public static final boolean CHECKS = false;
    public static final boolean DEBUG = false;
    public static long check(long a) { return a; }
}
J
cat > "$work/stub/org/lwjgl/system/Smoke.java" <<'J'
package org.lwjgl.system;
public class Smoke {
    static native int __fjc_native_load(String p);
    public static void main(String[] a) {
        __fjc_native_load("./liblwjgl.so");
        System.out.println(MemoryAccessJNI.getPointerSize());
    }
}
J
cp "$work/cp/org/lwjgl/system/MemoryAccessJNI.class" "$work/out/org/lwjgl/system/"
if ! javac -cp "$work/cp:$work/stub" -d "$work/out" "$work/stub/org/lwjgl/system/"*.java 2>"$work/j"; then
    echo "FAIL lwjgl_smoke (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/out/smoke" "$work/out/org/lwjgl/system/"*.class 2>"$work/h"; then
    echo "FAIL lwjgl_smoke (build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work/out" && ./smoke 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL lwjgl_smoke (exit $code): $out"; exit 1; }
[ "$(echo "$out" | tr -d '[:space:]')" = "8" ] || { echo "FAIL lwjgl_smoke (got '$out', want 8)"; exit 1; }
echo "ok   lwjgl_smoke (real shipped org.lwjgl.system.MemoryAccessJNI through the full native stack)"
