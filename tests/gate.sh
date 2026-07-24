#!/bin/sh
# Master gate for FastJavaC: build fastjavac, then the Java regression suite
# (0-live heap oracle) + the shape/freshness soundness suite. All must pass.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
( cd "$root" && cargo build ) || { echo "build failed"; exit 1; }
fail=0
sh "$root/tests/run.sh" || fail=1
sh "$root/tests/shape_soundness.sh" || fail=1
echo "========================================"
[ "$fail" -eq 0 ] && echo "GATE GREEN" || { echo "GATE RED"; exit 1; }
