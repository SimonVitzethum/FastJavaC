#!/bin/sh
# Tier-1 JIT opcode extension: idiv/irem/ldiv/lrem (checked — div-by-zero throws an
# ArithmeticException instead of a CPU #DE/SIGFPE), fcmpl/fcmpg/dcmpl/dcmpg (NaN
# ordering), float[]/double[] load/store, instanceof (registry TypeDesc walk) and
# ldc/ldc_w int/float constants. A host copy-and-patch-compiles each target method at
# runtime; results must match the reference JVM. Widget is AOT-compiled into the host
# so `new`/`instanceof` resolve against the FjcClass registry. x86-64 only.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; ex="$root/examples"; fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
case "$(uname -m)" in x86_64|amd64) ;; *) echo "ok   jitarith (skipped: non-x86_64)"; exit 0;; esac
[ -x "$fastjavac" ] || { echo "FAIL jitarith (fastjavac missing)"; exit 1; }
if ! javac -d "$work" "$ex/JitArith.java" "$ex/JitArithHost.java" "$ex/Widget.java" "$ex/Stats.java" 2>"$work/j"; then
    echo "FAIL jitarith (javac): $(head -1 "$work/j")"; exit 1; fi
if ! "$fastjavac" --dynamic -o "$work/host" "$work/JitArithHost.class" "$work/Widget.class" "$work/Stats.class" 2>"$work/h"; then
    echo "FAIL jitarith (build): $(cat "$work/h")"; exit 1; fi
out="$(cd "$work" && ./host 2>&1)"; code=$?
# div-by-zero must surface as a thrown ArithmeticException, never a hardware fault.
[ "$code" = 136 ] && { echo "FAIL jitarith (SIGFPE on div-by-zero): $out"; exit 1; }
[ "$code" = 139 ] && { echo "FAIL jitarith (segfault): $out"; exit 1; }
want="t_idiv=16
t_irem=4
t_ldiv=100
t_lrem=1
t_fa=4
t_da=6
t_fcmp=1
t_dcmp=1
t_instof=4
t_static=318
t_divz=42"
got="$(echo "$out" | grep '=')"
[ "$got" = "$want" ] || { echo "FAIL jitarith (opcode mismatch):"; echo "$out"; exit 1; }
echo "$out" | grep -q 'ArithmeticException' || { echo "FAIL jitarith (div-by-zero did not throw): $out"; exit 1; }
echo "ok   jitarith"
