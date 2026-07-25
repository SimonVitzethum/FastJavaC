#!/bin/sh
# Automatic JNI native-method binding: an ordinary `native` method auto-binds to
# its Java_<class>_<method> symbol in a System.load-ed lib, called via libffi.
# Builds a tiny libnativeadd.so on the fly. Output 7 / 10000000000.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL autobind (fastjavac missing)"; exit 1; }
cat > "$work/na.c" <<'CEOF'
#include <stdint.h>
int32_t Java_NativeAdd_addNative(void*e,void*c,int32_t a,int32_t b){(void)e;(void)c;return a+b;}
int64_t Java_NativeAdd_mulNative(void*e,void*c,int64_t a,int64_t b){(void)e;(void)c;return a*b;}
CEOF
cc -shared -fPIC "$work/na.c" -o "$work/libnativeadd.so" || { echo "FAIL autobind (cc lib)"; exit 1; }
if ! javac -d "$work" "$ex/NativeAdd.java" 2>"$work/j"; then
    echo "FAIL autobind (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/na" "$work"/NativeAdd*.class 2>"$work/h"; then
    echo "FAIL autobind (build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && ./na 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL autobind (exit $code): $out"; exit 1; }
[ "$(echo "$out" | tr '\n' ' ')" = "7 10000000000 " ] || { echo "FAIL autobind (got '$out', want 7/10000000000)"; exit 1; }
echo "ok   autobind"
