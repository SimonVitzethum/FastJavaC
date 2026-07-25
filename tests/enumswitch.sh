#!/bin/sh
# Enum pattern-switch via SwitchBootstraps.enumSwitch invokedynamic. The frontend
# resolves it statically (String label → enum-constant identity; null → −1; no
# match → N). Output must match the reference semantics (1,2,9,7) and heap-balance.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
[ -x "$fastjavac" ] || { echo "FAIL enumswitch (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/EnumPatternSwitch.java" 2>"$work/j"; then
    echo "FAIL enumswitch (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" -o "$work/es" "$work"/EnumPatternSwitch*.class 2>"$work/h"; then
    echo "FAIL enumswitch (build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && FASTLLVM_HEAPSTATS=1 ./es 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL enumswitch (exit $code): $out"; exit 1; }
got="$(echo "$out" | grep -E '^[0-9]+$' | tr '\n' ' ')"
[ "$got" = "1 2 9 7 " ] || { echo "FAIL enumswitch (got '$got', want '1 2 9 7'): $out"; exit 1; }
if echo "$out" | grep -q '\[heap\]' && ! echo "$out" | grep -q '0 still live'; then
    echo "FAIL enumswitch (heap leak): $(echo "$out" | grep '\[heap\]')"; exit 1; fi
echo "ok   enumswitch"
