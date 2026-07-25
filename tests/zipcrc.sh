#!/bin/sh
# End-to-end JNI bridge in the real runtime: a fastjavac-compiled Java program uses
# java.util.zip.CRC32, whose checksum comes from the JDK's OWN libzip.so native leaf
# via jrt_jni_crc32 (dlopen libjvm RTLD_GLOBAL for its JVM_* + libzip; minimal JNIEnv
# over the fastjavac byte[]). Expect crc32("hello") = 907060870. Needs a reference JDK
# (JAVA_HOME or /usr/lib/jvm/*); skips cleanly otherwise.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
zip="$root/stdlib/out/java/util/zip"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL zipcrc (fastjavac missing)"; exit 1; }
JH="${JAVA_HOME:-}"
[ -n "$JH" ] || JH="$(dirname "$(dirname "$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)")" 2>/dev/null)"
[ -f "$JH/lib/server/libjvm.so" ] && [ -f "$JH/lib/libzip.so" ] || {
    echo "ok   zipcrc (skipped: no reference JDK libjvm/libzip)"; exit 0; }
sh "$root/stdlib/build.sh" >/dev/null 2>&1
if ! javac -cp "$root/stdlib/out" -d "$work" "$ex/ZipCrc.java" 2>"$work/j"; then
    echo "FAIL zipcrc (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/zc" "$work"/ZipCrc*.class "$zip"/*.class 2>"$work/h"; then
    echo "FAIL zipcrc (build): $(cat "$work/h")"; exit 1; fi
out="$(JAVA_HOME="$JH" "$work/zc" 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL zipcrc (exit $code): $out"; exit 1; }
[ "$(echo "$out" | tr -d '[:space:]')" = "907060870" ] || { echo "FAIL zipcrc (got '$out', want 907060870)"; exit 1; }
echo "ok   zipcrc (real JDK libzip CRC32 via runtime JNI bridge)"
