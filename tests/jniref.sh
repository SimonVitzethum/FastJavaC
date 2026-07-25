#!/bin/sh
# JNI local-reference lifetime: a native retrieves/creates object refs and discards
# them (must be freed at native return via the local-ref frame) or returns one (kept).
# Heap must balance. Needs jni.h; skips otherwise.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL jniref (fastjavac missing)"; exit 1; }
JH="${JAVA_HOME:-}"; [ -n "$JH" ] || JH="$(dirname "$(dirname "$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)")" 2>/dev/null)"
[ -f "$JH/include/jni.h" ] || { echo "ok   jniref (skipped: no jni.h)"; exit 0; }
cat > "$work/or.c" <<'CEOF'
#include <jni.h>
jint Java_ORef_probe(JNIEnv*e,jclass c,jobject o){(void)c;jclass k=(*e)->GetObjectClass(e,o);
 jfieldID nf=(*e)->GetFieldID(e,k,"name","Ljava/lang/String;");jstring nm=(*e)->GetObjectField(e,o,nf);
 jmethodID mk=(*e)->GetMethodID(e,k,"make","()Ljava/lang/String;");jstring md=(*e)->CallObjectMethod(e,o,mk);
 const char*a=(*e)->GetStringUTFChars(e,nm,0);const char*b=(*e)->GetStringUTFChars(e,md,0);
 int la=0;while(a[la])la++;int lb=0;while(b[lb])lb++;
 (*e)->ReleaseStringUTFChars(e,nm,a);(*e)->ReleaseStringUTFChars(e,md,b);return la+lb;}
jstring Java_ORef_makeNative(JNIEnv*e,jclass c){(void)c;return (*e)->NewStringUTF(e,"hi");}
CEOF
cc -shared -fPIC -I "$JH/include" -I "$JH/include/linux" "$work/or.c" -o "$work/liboref.so" || { echo "FAIL jniref (cc)"; exit 1; }
javac -d "$work" "$ex/ORef.java" 2>"$work/j" || { echo "FAIL jniref (javac): $(head -1 "$work/j")"; exit 1; }
"$fastjavac" --dynamic -o "$work/or" "$work/ORef.class" 2>"$work/h" || { echo "FAIL jniref (build): $(cat "$work/h")"; exit 1; }
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./or 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jniref (exit $code): $out"; exit 1; }
got="$(echo "$out" | grep -E '^(11|hi)$' | tr '\n' ' ')"
[ "$got" = "11 hi " ] || { echo "FAIL jniref (got '$got', want 11/hi): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL jniref (heap leak — local-ref frame): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   jniref"
