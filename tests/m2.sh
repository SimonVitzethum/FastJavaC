#!/bin/sh
# M2 (compile-on-load cache) end-to-end test: a --dynamic host loads a bytecode .jar
# at runtime; the loader compiles it to a native module via a fastjavac subprocess
# (ahead-of-load, not an in-process JIT), caches it, and runs it. A second run with
# FASTJAVAC pointed at a nonexistent binary must still succeed via the cache.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples"
fastjavac="$root/target/debug/fastjavac"
work="$(mktemp -d)"
cache="$(mktemp -d)"
trap 'rm -rf "$work" "$cache"' EXIT

[ -x "$fastjavac" ] || { echo "FAIL m2 (fastjavac missing)"; exit 1; }

if ! javac -d "$work/mod" "$ex/ModJar.java" 2>"$work/jerr"; then
    echo "FAIL m2 (javac mod): $(head -1 "$work/jerr")"; exit 1
fi
( cd "$work/mod" && jar cfe "$work/modjar.jar" ModJar ModJar.class ) || { echo "FAIL m2 (jar)"; exit 1; }
if ! javac -d "$work" "$ex/JarHost.java" 2>"$work/jerr2"; then
    echo "FAIL m2 (javac host): $(head -1 "$work/jerr2")"; exit 1
fi
if ! "$fastjavac" --dynamic -o "$work/jhost" "$work/JarHost.class" 2>"$work/herr"; then
    echo "FAIL m2 (host build): $(cat "$work/herr")"; exit 1
fi

# Run 1: fresh cache -> compiles the jar to a native module and runs it.
out1="$(cd "$work" && FASTJAVAC="$fastjavac" FASTJAVAC_CACHE="$cache" ./jhost 2>&1)"; c1=$?
if [ "$c1" != 0 ]; then echo "FAIL m2 (run1 exit $c1): $out1"; exit 1; fi
if [ "$(echo "$out1" | grep -c '^99$')" -lt 1 ] || ! echo "$out1" | grep -q '^host-ok$'; then
    echo "FAIL m2 (run1 output): $out1"; exit 1
fi
if [ "$(ls -1 "$cache"/fjc-*.so 2>/dev/null | wc -l)" -lt 1 ]; then
    echo "FAIL m2 (no cached module produced)"; exit 1
fi

# Run 2: cache hit — point FASTJAVAC at a nonexistent binary so any recompile fails.
out2="$(cd "$work" && FASTJAVAC=/nonexistent/fastjavac FASTJAVAC_CACHE="$cache" ./jhost 2>&1)"; c2=$?
if [ "$c2" != 0 ]; then echo "FAIL m2 (run2 cache-hit exit $c2): $out2"; exit 1; fi
if ! echo "$out2" | grep -q '^host-ok$'; then echo "FAIL m2 (run2 output): $out2"; exit 1; fi

echo "ok   m2_compile_on_load"
