#!/bin/sh
# A static native uses its jclass arg (GetStaticMethodID + CallStaticIntMethod on it).
# Needs jni.h; skips otherwise. Expect 142.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL jnistatic (fastjavac missing)"; exit 1; }
JH="${JAVA_HOME:-}"; [ -n "$JH" ] || JH="$(dirname "$(dirname "$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)")" 2>/dev/null)"
[ -f "$JH/include/jni.h" ] || { echo "ok   jnistatic (skipped: no jni.h)"; exit 0; }
cat > "$work/sc.c" <<'CEOF'
#include <jni.h>
jint Java_SCls_dispatch(JNIEnv*e,jclass cls,jint x){jmethodID m=(*e)->GetStaticMethodID(e,cls,"helper","(I)I");return (*e)->CallStaticIntMethod(e,cls,m,x)+100;}
CEOF
cc -shared -fPIC -I "$JH/include" -I "$JH/include/linux" "$work/sc.c" -o "$work/libscls.so" || { echo "FAIL jnistatic (cc)"; exit 1; }
javac -d "$work" "$ex/SCls.java" 2>"$work/j" || { echo "FAIL jnistatic (javac): $(head -1 "$work/j")"; exit 1; }
"$fastjavac" --dynamic -o "$work/sc" "$work/SCls.class" 2>"$work/h" || { echo "FAIL jnistatic (build): $(cat "$work/h")"; exit 1; }
out="$(cd "$work" && ./sc 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jnistatic (exit $code): $out"; exit 1; }
[ "$(echo "$out" | tr -d '[:space:]')" = "142" ] || { echo "FAIL jnistatic (got '$out', want 142)"; exit 1; }
echo "ok   jnistatic"
