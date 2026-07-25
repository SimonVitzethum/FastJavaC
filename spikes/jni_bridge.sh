#!/bin/sh
# Reproducible driver for the JNI/JVM_* bridge spike (NATIVE-STRATEGY.md).
# Proves: a REAL JDK native leaf (libzip.so's CRC32) can be called through a
# minimal bridge onto fastjavac's object model. The bridge = our own libjvm.so
# providing the versioned JVM_* upcalls + a minimal JNIEnv over the array layout.
#
# Steps: (1) find the reference JDK; (2) generate a fake libjvm.so that stubs
# every SUNWprivate_1.1 JVM_*/jio_* symbol libjava/libzip import (this is the
# finite "VM interface" — measured ~159 here); (3) a fake libjava.so stubbing the
# few JNU_* helpers libzip imports; (4) build + run the spike, LD_PRELOADing the
# fakes so libzip's NEEDED libjvm/libjava resolve to ours. Expected CRC32("hello")
# = 907060870 (== zlib.crc32).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
JDK="${JDK:-$(dirname "$(dirname "$(readlink -f "$(command -v java 2>/dev/null)")")" 2>/dev/null)}"
[ -d "$JDK/include" ] || JDK=/usr/lib/jvm/java-25-graalvm
LZ="$(find "$JDK" -name libzip.so 2>/dev/null | head -1)"
LJA="$(find "$JDK" -name libjava.so 2>/dev/null | head -1)"
[ -n "$LZ" ] && [ -n "$LJA" ] && [ -f "$JDK/include/jni.h" ] || {
    echo "ok   jni_bridge (skipped: no reference JDK with libzip/jni.h at $JDK)"; exit 0; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# (2) fake libjvm.so: stub every SUNWprivate_1.1 symbol libjava+libzip import.
nm -D -u "$LJA" "$LZ" 2>/dev/null | grep SUNWprivate | grep -oE '[A-Za-z_][A-Za-z0-9_]+@' | tr -d '@' | sort -u > "$work/jvmsyms.txt"
n=$(wc -l < "$work/jvmsyms.txt")
{ echo '#include <stddef.h>'; while read s; do echo "void *$s(void){return NULL;}"; done < "$work/jvmsyms.txt"; } > "$work/fakejvm.c"
{ echo 'SUNWprivate_1.1 {'; echo ' global:'; sed 's/$/;/' "$work/jvmsyms.txt"; echo ' local: *;'; echo '};'; } > "$work/jvm.map"
cc -shared -fPIC -Wl,-soname,libjvm.so -Wl,--version-script="$work/jvm.map" "$work/fakejvm.c" -o "$work/libjvm.so" || { echo "FAIL jni_bridge (build libjvm)"; exit 1; }

# (3) fake libjava.so: stub the JNU_*/jio_* helpers libzip imports from libjava.
nm -D -u "$LZ" 2>/dev/null | grep -oE 'JNU_[A-Za-z]+|jio_[a-z]+|getErrorString' | sort -u > "$work/javasyms.txt"
{ echo '#include <stddef.h>'; while read s; do echo "void *$s(void){return NULL;}"; done < "$work/javasyms.txt"; } > "$work/fakejava.c"
cc -shared -fPIC -Wl,-soname,libjava.so "$work/fakejava.c" -o "$work/libjava.so" || { echo "FAIL jni_bridge (build libjava)"; exit 1; }

# (4) build + run the bridge.
cc "$here/jni_bridge.c" -I "$JDK/include" -I "$JDK/include/linux" -ldl -o "$work/jnispike" || { echo "FAIL jni_bridge (build spike)"; exit 1; }
out="$(LD_PRELOAD="$work/libjvm.so $work/libjava.so" "$work/jnispike" "$LZ" 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jni_bridge (exit $code): $out"; exit 1; }
if [ "$(echo "$out" | grep -c '= 907060870')" != 2 ]; then
    echo "FAIL jni_bridge (wrong CRC, stubbed $n JVM_* symbols): $out"; exit 1; fi
echo "ok   jni_bridge (called REAL libzip CRC32 via bridge; stubbed $n versioned JVM_* upcalls)"
