#!/bin/sh
# NewObject (native constructs a Java object) + Call<T>MethodA (jvalue[] args). The
# constructed object must be freed at the native return (local-ref frame). Needs
# jni.h; skips otherwise. Expect 77, heap-balanced.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL jninew (fastjavac missing)"; exit 1; }
JH="${JAVA_HOME:-}"; [ -n "$JH" ] || JH="$(dirname "$(dirname "$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)")" 2>/dev/null)"
[ -f "$JH/include/jni.h" ] || { echo "ok   jninew (skipped: no jni.h)"; exit 0; }
cat > "$work/no.c" <<'CEOF'
#include <jni.h>
jint Java_NObj_build(JNIEnv*e,jclass cls){(void)cls;jclass pc=(*e)->FindClass(e,"NPoint");
 jmethodID ct=(*e)->GetMethodID(e,pc,"<init>","(II)V");jobject p=(*e)->NewObject(e,pc,ct,3,4);
 jmethodID sm=(*e)->GetMethodID(e,pc,"sum","()I");int s=(*e)->CallIntMethod(e,p,sm);
 jmethodID sc=(*e)->GetMethodID(e,pc,"scale","(I)I");jvalue a[1];a[0].i=10;int r=(*e)->CallIntMethodA(e,p,sc,a);
 return s+r;}
CEOF
cc -shared -fPIC -I "$JH/include" -I "$JH/include/linux" "$work/no.c" -o "$work/libno.so" || { echo "FAIL jninew (cc)"; exit 1; }
javac -d "$work" "$ex/NPoint.java" "$ex/NObj.java" 2>"$work/j" || { echo "FAIL jninew (javac): $(head -1 "$work/j")"; exit 1; }
"$fastjavac" --dynamic -o "$work/no" "$work/NObj.class" "$work/NPoint.class" 2>"$work/h" || { echo "FAIL jninew (build): $(cat "$work/h")"; exit 1; }
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./no 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jninew (exit $code): $out"; exit 1; }
echo "$out" | grep -qx 77 || { echo "FAIL jninew (got '$out', want 77)"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jninew (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   jninew"
