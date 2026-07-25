#!/bin/sh
# Native → Java method callbacks: GetMethodID/CallIntMethod (instance + virtual
# override) and GetStaticMethodID/CallStaticIntMethod, via libffi over the native
# ABI. Needs jni.h (a JDK); skips otherwise. Expect 58.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL jnicall (fastjavac missing)"; exit 1; }
JH="${JAVA_HOME:-}"; [ -n "$JH" ] || JH="$(dirname "$(dirname "$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)")" 2>/dev/null)"
[ -f "$JH/include/jni.h" ] || { echo "ok   jnicall (skipped: no jni.h)"; exit 0; }
cat > "$work/cb.c" <<'CEOF'
#include <jni.h>
jint Java_Callback_run(JNIEnv*e,jclass c,jobject o){(void)c;jclass k=(*e)->GetObjectClass(e,o);
 jmethodID d=(*e)->GetMethodID(e,k,"doubleIt","(I)I");int r1=(*e)->CallIntMethod(e,o,d,21);
 jmethodID g=(*e)->GetMethodID(e,k,"greet","()I");int r2=(*e)->CallIntMethod(e,o,g);
 jmethodID s=(*e)->GetStaticMethodID(e,k,"triple","(I)I");int r3=(*e)->CallStaticIntMethod(e,k,s,3);
 return r1+r2+r3;}
CEOF
cc -shared -fPIC -I "$JH/include" -I "$JH/include/linux" "$work/cb.c" -o "$work/libcb.so" || { echo "FAIL jnicall (cc)"; exit 1; }
javac -d "$work" "$ex/Base.java" "$ex/Callback.java" 2>"$work/j" || { echo "FAIL jnicall (javac): $(head -1 "$work/j")"; exit 1; }
"$fastjavac" --dynamic -o "$work/cb" "$work/Callback.class" "$work/Base.class" 2>"$work/h" || { echo "FAIL jnicall (build): $(cat "$work/h")"; exit 1; }
out="$(cd "$work" && ./cb 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jnicall (exit $code): $out"; exit 1; }
[ "$(echo "$out" | tr -d '[:space:]')" = "58" ] || { echo "FAIL jnicall (got '$out', want 58)"; exit 1; }
echo "ok   jnicall"
