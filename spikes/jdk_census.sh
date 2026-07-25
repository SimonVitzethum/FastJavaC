#!/bin/sh
# JDK-compile census (MC-PAPER-ROADMAP.md §10 step 1): feed real java.base classes to the
# FastJavaC frontend and tally how far bytecode->IR lowering gets + the gap list.
# Frontend-only (--emit-ir); does NOT test native methods, backend, or the runtime engine.
#
# Usage: sh spikes/jdk_census.sh [JAVA_HOME] [N]
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
fjc="$root/target/debug/fastjavac"
jvm="${1:-/usr/lib/jvm/java-25-graalvm}"
N="${2:-600}"
[ -x "$fjc" ] || { echo "build fastjavac first (cargo build)"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
"$jvm/bin/jimage" extract --dir "$work/jb" "$jvm/lib/modules" 2>/dev/null || {
    echo "could not extract JDK image from $jvm/lib/modules"; exit 1; }
jb="$work/jb/java.base"

errs="$work/errs.txt"; : > "$errs"
n=0
for c in $(find "$jb" -name '*.class' | sort | head -"$N"); do
    "$fjc" --emit-ir "$c" 2>&1 | head -1 >> "$errs"
    n=$((n+1))
done

echo "attempted:                 $n"
echo "lowered OK (standalone):   $(grep -vc 'fastjavac:' "$errs")"
echo "errored:                   $(grep -c 'fastjavac:' "$errs")"
echo "  dependency (missing cls): $(grep -Ec 'not in the closed-world input|not in the input|class not in' "$errs")"
echo "  true opcode gaps:         $(grep -Ec 'opcode 0x' "$errs")"
echo
echo "distinct unsupported opcodes:"
grep -oE 'opcode 0x[0-9a-fA-F]+' "$errs" | sort | uniq -c | sort -rn
