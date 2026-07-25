#!/bin/sh
# JNIEnv string slots: a native method takes a Java String (GetStringUTFChars) and
# returns one (NewStringUTF). Needs jni.h (a JDK); skips otherwise.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL strnative (fastjavac missing)"; exit 1; }
JH="${JAVA_HOME:-}"; [ -n "$JH" ] || JH="$(dirname "$(dirname "$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)")" 2>/dev/null)"
[ -f "$JH/include/jni.h" ] || { echo "ok   strnative (skipped: no jni.h)"; exit 0; }
cat > "$work/ls.c" <<'CEOF'
#include <jni.h>
#include <string.h>
jint Java_StrNative_strlenNative(JNIEnv*e,jclass c,jstring s){(void)c;const char*p=(*e)->GetStringUTFChars(e,s,0);int n=(int)strlen(p);(*e)->ReleaseStringUTFChars(e,s,p);return n;}
jstring Java_StrNative_echoUpper(JNIEnv*e,jclass c,jstring s){(void)c;const char*p=(*e)->GetStringUTFChars(e,s,0);char b[256];int i=0;for(;p[i]&&i<255;i++)b[i]=(p[i]>='a'&&p[i]<='z')?p[i]-32:p[i];b[i]=0;(*e)->ReleaseStringUTFChars(e,s,p);return (*e)->NewStringUTF(e,b);}
CEOF
cc -shared -fPIC -I "$JH/include" -I "$JH/include/linux" "$work/ls.c" -o "$work/libstrn.so" || { echo "FAIL strnative (cc)"; exit 1; }
javac -d "$work" "$ex/StrNative.java" 2>"$work/j" || { echo "FAIL strnative (javac): $(head -1 "$work/j")"; exit 1; }
"$fastjavac" --dynamic -o "$work/sn" "$work"/StrNative*.class 2>"$work/h" || { echo "FAIL strnative (build): $(cat "$work/h")"; exit 1; }
out="$(cd "$work" && ./sn 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL strnative (exit $code): $out"; exit 1; }
[ "$(echo "$out" | tr '\n' ' ')" = "11 3 A " ] || { echo "FAIL strnative (got '$out', want 11/3/A)"; exit 1; }
echo "ok   strnative"
