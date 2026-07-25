#!/bin/sh
# General JNI field access via the FjcClass registry: a native reads/writes object
# fields (GetObjectClass/GetFieldID/Get-SetIntField). Needs jni.h (a JDK); skips else.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL jnifield (fastjavac missing)"; exit 1; }
JH="${JAVA_HOME:-}"; [ -n "$JH" ] || JH="$(dirname "$(dirname "$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)")" 2>/dev/null)"
[ -f "$JH/include/jni.h" ] || { echo "ok   jnifield (skipped: no jni.h)"; exit 0; }
cat > "$work/fl.c" <<'CEOF'
#include <jni.h>
jint Java_FieldTest_sumFields(JNIEnv*e,jclass c,jobject o){(void)c;jclass k=(*e)->GetObjectClass(e,o);jfieldID a=(*e)->GetFieldID(e,k,"a","I");jfieldID b=(*e)->GetFieldID(e,k,"b","I");return (*e)->GetIntField(e,o,a)+(*e)->GetIntField(e,o,b);}
void Java_FieldTest_bump(JNIEnv*e,jclass c,jobject o){(void)c;jclass k=(*e)->GetObjectClass(e,o);jfieldID a=(*e)->GetFieldID(e,k,"a","I");(*e)->SetIntField(e,o,a,(*e)->GetIntField(e,o,a)+10);}
jint Java_FieldTest_refCheck(JNIEnv*e,jclass c,jobject o){(void)c;jobject g=(*e)->NewGlobalRef(e,o);jclass k=(*e)->FindClass(e,"FieldTest");int is=(*e)->IsInstanceOf(e,g,k);int sm=(*e)->IsSameObject(e,g,o);(*e)->DeleteGlobalRef(e,g);return is*10+sm;}
CEOF
cc -shared -fPIC -I "$JH/include" -I "$JH/include/linux" "$work/fl.c" -o "$work/libfield.so" || { echo "FAIL jnifield (cc)"; exit 1; }
javac -d "$work" "$ex/FieldTest.java" 2>"$work/j" || { echo "FAIL jnifield (javac): $(head -1 "$work/j")"; exit 1; }
"$fastjavac" --dynamic -o "$work/ft" "$work"/FieldTest*.class 2>"$work/h" || { echo "FAIL jnifield (build): $(cat "$work/h")"; exit 1; }
out="$(cd "$work" && ./ft 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jnifield (exit $code): $out"; exit 1; }
[ "$(echo "$out" | tr '\n' ' ')" = "42 40 11 " ] || { echo "FAIL jnifield (got '$out', want 42/40/11)"; exit 1; }
echo "ok   jnifield"
