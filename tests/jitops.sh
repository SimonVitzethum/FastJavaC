#!/bin/sh
# Tier-1 JIT with the extended opcode set: int/long shifts (shl/shr/ushr), bitwise
# (and/or/xor), i2b narrowing, lneg, lcmp. A host copy-and-patch-compiles the target
# methods at runtime; results must match the reference JVM (bitops=5, longops=35).
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jitops (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitops (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/JitOps.java" "$ex/JitOpsHost.java" 2>"$work/j"; then
    echo "FAIL jitops (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/host" "$work/JitOpsHost.class" 2>"$work/h"; then
    echo "FAIL jitops (build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && ./host 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL jitops (exit $code): $out"; exit 1; }
got="$(echo "$out" | tr '\n' ' ')"
[ "$got" = "5 35 -1589934580 " ] || { echo "FAIL jitops (got '$got', want '5 35 -1589934580' — opcode bug): $out"; exit 1; }
echo "ok   jitops"
