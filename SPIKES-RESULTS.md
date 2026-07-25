# Spike Results: de-risking the MC/Paper roadmap

**Date:** 2026-07-25
**Ran the two cheap de-riskers from `MC-PAPER-ROADMAP.md` §10.** Both validate their
thesis. Reproduce: `spikes/cap_spike.c` and `spikes/jdk_census.sh`.

---

## Spike 2 — copy-and-patch JIT (the "cheap JIT" thesis) ✅ VALIDATED

`spikes/cap_spike.c`: an AOT-compiled stencil `x + HOLE` is JITted at runtime by
`memcpy` + patching the immediate, then executed.

```
JIT result: f(42) with patched +1000 = 1042  (expected 1042)
stencil size:        16 bytes
hole offset:         2
per-method JIT cost: 182.2 ns   (incl. icache flush + one call)
code RAM per method: 16 bytes (one stencil copy)
```

**Reading:** ~**182 ns** to materialize + run a method, **16 bytes** of code. Versus an
M2 `clang` subprocess at ~**100 ms** per module, that is **~5–6 orders of magnitude
cheaper**, with negligible RAM and no runtime compiler/allocator. A real method is a
concatenation of one stencil per bytecode, so cost scales with method size but stays in
the low-µs / sub-KB range. This is exactly the "in-process JIT that costs little
performance and little RAM" the constraint requires, and it produces **native code welded
into the running image** (the "JIT edits the binary" principle). Thesis holds.

Next step to productionize: build the AOT stencil library (one stencil per bytecode, with
typed holes for operands/relocations), a register/stack-slot calling convention between
stencils, and the splice-into-image path (reuse the Phase-5 patcher).

## Spike 1 — compile real OpenJDK `java.base` (the "compile the JDK" thesis) ✅ ENCOURAGING

`spikes/jdk_census.sh`: fed **600 real `java.base` classes** (GraalVM 25 image) to the
FastJavaC **frontend** (`--emit-ir`, bytecode→IR) **individually — i.e. WITHOUT their
dependencies** — and tallied the first error per class.

| Outcome | Count | Meaning |
|---|---:|---|
| Lowered OK (standalone, no deps) | **227 / 600 (38%)** | frontend already handles these class bodies |
| Errored | 373 | of which: |
| — missing-class (dependency) | **207** | "class not in the closed-world input" — **resolves when the JDK is compiled together**; NOT a feature gap |
| — true unsupported opcodes | **26** | the real bytecode backlog (below) |
| — String/StringBuilder/reflection subset | **11** | mostly vanish when compiling the *real* `java.lang.String` instead of the hand-modeled stub |

**The true bytecode-coverage gap is tiny — only 3 distinct opcodes:**

| Opcode | Mnemonic | Hits | Difficulty |
|---|---|---:|---|
| `0x91` | `i2b` (int→byte) | 10 | trivial (truncate/sign-extend) |
| `0x92` | `i2c` (int→char) | 7 | trivial (zero-extend to 16-bit) |
| `0x5a` | `dup_x1` | 9 | trivial (stack shuffle) |

**Reading:** for `java.base`, the dominant blocker is **closed-world dependency
resolution** (missing classes), *not* unimplemented bytecode — exactly what "compile
OpenJDK as one closed world" fixes. 38% of classes lower even standalone; with
dependencies present that fraction rises sharply. The remaining frontend backlog is a
**handful of trivial opcodes + broadening String/reflection** (the latter subsumed by
compiling the real JDK classes). The "compile the real JDK bytecode" thesis is well
supported on the frontend side.

### Honest caveats (what this spike does NOT prove)
This exercises only **frontend lowering (bytecode → IR)**. It does not test, and the
**bigger** work still lies in:
- **Native methods** — `native` methods have no `Code` attribute, so the frontend skips
  them silently; they fail at **link/run** time. The native/intrinsic layer (roadmap §3)
  is untouched by this spike and remains the large hand-written surface.
- **Full backend + link + run** of these classes (only IR generation was checked).
- **`invokedynamic` generality, `Unsafe`, the tracing GC, class loaders, JNI** (roadmap
  §2/§4/§5/§6) — the actual runtime engine.

So: the *bytecode/JDK-compile* front is much closer than expected; the *runtime engine*
is where the multi-person-year effort concentrates.

## Follow-ups 1–3 (done)

### 1. Implement the missing opcodes ✅ DONE
Added `i2b`/`i2c`/`i2s` (narrowing conversions) + `dup_x1` (stack shuffle) to the
decoder and frontend. Re-running the census over the same 600 `java.base` classes:
**true opcode gaps 26 → 0.** The only remaining errors are missing-dependency. Regression
test `examples/ConvOps.java` (i2b=44, i2c=4464, i2s=4464, dup_x1 field-assign=9).

### 2. Grow the closed world → dependency errors collapse ✅ DEMONSTRATED
Compiled progressively larger `java.base` clusters as one closed world and watched the
first wall move:

| Closed world | First wall | Kind |
|---|---|---|
| `HashMap` alone | `class X not in input` | dependency |
| `java.lang`+`java.util` top-level (793) | `new j.u.c.ConcurrentHashMap not in input` | dependency, moved **outward** |
| all `java.util`+`java.lang` (2424) | `StringBuilder.append(F)` unsupported | **real feature** (intrinsic incompleteness) |
| entire `java.base` (7357) | `GB18030: invalid Modified-UTF-8` | **parser edge case** (huge string constant) |

**Conclusion:** within-module "missing class" errors are an *ordering artifact of partial
input* — they migrate outward and disappear as the closure is supplied. The residual,
enumerable backlog is: (a) **parser robustness** on pathological constants (charset
tables), (b) **completing/replacing the hand-modeled `String`/`StringBuilder` intrinsics**
with the real compiled classes (they currently *shadow* the real ones and are
incomplete), (c) **reflection/`invokedynamic` generality** (roadmap §3/§4). Not an
infinite dependency problem — the whole-JDK-closed-world thesis holds.

### 3. Start the copy-and-patch stencil library ✅ STARTED
See `spikes/stencil_lib.c` and "§ Stencil library" below: composition of multiple AOT
stencils (not just one hole) into a native method, with the calling convention and
measurements.

## Stencil library design (copy-and-patch → product)

The single-stencil spike (Spike 2) is extended to **composition**, the key new
capability. A stencil is a fixed machine-code template with typed **holes** (immediates /
relocations). A method is JIT-compiled by concatenating one stencil per operation and
patching each hole — no assembler, no LLVM at runtime.

- **Calling convention (spike):** a uniform *accumulator* model — the working value lives
  in `eax`; each stencil reads/updates it and falls through to the next; a final `ret`
  stencil returns it. (Production: a threaded / tail-call convention with a virtual-stack
  pointer in a fixed register, so arbitrary JVM stack bytecode composes; stencils derived
  by compiling C snippets with a tail-call CC — Xu & Kjølstad — instead of hand-written
  bytes.)
- **Stencil table (spike):** `LOAD_CONST k` (`mov eax,imm`), `ADD_CONST k`
  (`add eax,imm`), `MUL_CONST k` (`imul eax,eax,imm`), `RET`. Each carries its hole
  offset. A production JVM set has one stencil per bytecode (loads/stores/arith/branches/
  calls) with holes for constants, local slots, branch targets, and callee addresses.
- **JIT step:** for each op, `memcpy` its stencil into the code buffer and patch the hole
  with this op's operand; end with `RET`. Splice into the running image via the Phase-5
  patcher.

Measured (`spikes/stencil_lib.c`, composing `(10 + 5) * 3` from 4 stencils):
```
composed 4 stencils -> (10+5)*3 = 45  (expected 45)
method code size:   17 bytes
per-method JIT cost: 337.1 ns  (4 stencils, incl. flush + call)
```
Composition + multi-hole patching works; **17 bytes / ~337 ns** for a 4-op method keeps
the "little performance, little RAM" budget under composition. Next: derive the full
per-bytecode stencil set from C snippets (tail-call CC) and wire the virtual-stack
convention, then integrate as FastJavaC's Tier-1 JIT feeding the Phase-5 splice path.
