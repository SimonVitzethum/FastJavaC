#!/bin/sh
# Instance `native` auto-bind (receiver as jobject) + IEEE-754 bit intrinsics.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL instnative (fastjavac missing)"; exit 1; }
cat > "$work/li.c" <<'CEOF'
#include <stdint.h>
int32_t Java_InstNative_getVal(void*e,void*t){(void)e;(void)t;return 99;}
int32_t Java_InstNative_addTo(void*e,void*t,int32_t x){(void)e;(void)t;return x+1;}
CEOF
cc -shared -fPIC "$work/li.c" -o "$work/libinst.so" || { echo "FAIL instnative (cc)"; exit 1; }
javac -d "$work" "$ex/InstNative.java" 2>"$work/j" || { echo "FAIL instnative (javac): $(head -1 "$work/j")"; exit 1; }
"$fastjavac" --dynamic -o "$work/in" "$work"/InstNative*.class 2>"$work/h" || { echo "FAIL instnative (build): $(cat "$work/h")"; exit 1; }
out="$(cd "$work" && ./in 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL instnative (exit $code): $out"; exit 1; }
[ "$(echo "$out" | tr '\n' ' ')" = "99 42 1 4 " ] || { echo "FAIL instnative (got '$out', want 99/42/1/4)"; exit 1; }
echo "ok   instnative"
